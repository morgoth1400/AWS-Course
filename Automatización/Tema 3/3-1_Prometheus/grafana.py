import boto3
import time
from botocore.exceptions import ClientError, WaiterError 
import json

# --- ⚠️ CONFIGURACIÓN REQUERIDA (NO MODIFICAR ESTOS VALORES) ⚠️ ---
REGION = 'us-east-1' 
KEY_NAME = 'vockey'                                     
PROMETHEUS_INSTANCE_ID = 'i-08555ccc89910b756'          
# Si usas una AMI de Ubuntu, debes usar el AMI ID correcto para Ubuntu. 
# Si usas el mismo AMI ID de Amazon Linux, el script fallará.
# Asumo que esta AMI ID es de Ubuntu o se mapea a Ubuntu en tu entorno.
AMI_ID = 'ami-0ecb62995f68bb549'                         
PROMETHEUS_SERVER_URL = 'http://54.163.4.160:9090'     
NEW_ADMIN_PASSWORD = 'adminadmin'             
SSM_INSTANCE_PROFILE_NAME = 'LabInstanceProfile'        
INSTANCE_TYPE = 't3.small'                             
EC2_NAME_TAG = 'MON'
# -----------------------------------------------------------

# --- Contenido del User Data (Instalación de Grafana en UBUNTU - CORREGIDO) ---
# Usa APT y UFW, que son los comandos correctos para Ubuntu/Debian.
GRAFANA_USER_DATA = """#!/bin/bash
# Actualizar lista de paquetes e instalar dependencias
sudo apt update -y
sudo apt install -y apt-transport-https software-properties-common wget

# Agregar clave GPG de Grafana
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -

# Agregar repositorio de Grafana
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"

# Instalar Grafana
sudo apt update -y
sudo apt install grafana -y

# Iniciar y habilitar el servicio de Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# Abrir puerto 3000 para acceso a Grafana usando ufw (Firewall de Ubuntu)
sudo apt install ufw -y  # Asegura que ufw esté instalado
sudo ufw allow 3000/tcp
sudo ufw --force enable
"""

# --- Comando SSM (Post-configuración: Data Source y Contraseña) ---
SSM_CONFIG_COMMANDS = f"""
#!/bin/bash
# Esperamos un momento para que Grafana se inicie completamente
sleep 60 

echo "1. Configurando Prometheus como Data Source en Grafana..."

# Crear archivo de configuración de Data Source (JSON)
cat <<EOF > /tmp/prometheus_datasource.json
{{
 "name": "Prometheus_SSM",
 "type": "prometheus",
 "url": "{PROMETHEUS_SERVER_URL}",
 "access": "proxy",
 "isDefault": true
}}
EOF

# Obtener token de autenticación por defecto (admin:admin)
AUTH_TOKEN=$(echo -n "admin:admin" | base64)

# Intentar añadir la fuente de datos a través de la API
curl -X POST http://localhost:3000/api/datasources \
 -H "Content-Type: application/json" \
 -H "Authorization: Basic $AUTH_TOKEN" \
 --data @/tmp/prometheus_datasource.json

echo "Data Source Prometheus_SSM añadido."

# 2. Modificar la contraseña de administrador (de admin:admin a la nueva)
echo "Cambiando la contraseña por defecto de admin:admin..."
curl -X PUT http://localhost:3000/api/user/password \
 -H "Content-Type: application/json" \
 -H "Authorization: Basic $AUTH_TOKEN" \
 --data '{{"oldPassword": "admin", "newPassword": "{NEW_ADMIN_PASSWORD}", "confirmNew": "{NEW_ADMIN_PASSWORD}"}}'

echo "Configuración de Data Source y contraseña completada."
"""

# Inicialización de Clientes (Globales)
ec2 = boto3.client('ec2', region_name=REGION)
ssm = boto3.client('ssm', region_name=REGION)


def get_prometheus_network_info(prometheus_instance_id):
    """Obtiene el VPC ID y Subnet ID del servidor Prometheus."""
    print(f"--- 1. Buscando información de red del servidor Prometheus ({prometheus_instance_id}) ---")
    try:
        response = ec2.describe_instances(InstanceIds=[prometheus_instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        vpc_id = instance['VpcId']
        subnet_id = instance['SubnetId']
        print(f"  VPC ID encontrado: {vpc_id}, Subnet ID encontrado: {subnet_id}")
        return vpc_id, subnet_id
    except ClientError as e:
        print(f"  ❌ Error al obtener información del servidor Prometheus: {e}")
        raise
    except IndexError:
        print(f"  ❌ No se encontró la instancia con ID: {prometheus_instance_id}")
        raise

def create_security_group(vpc_id):
    """Crea o reutiliza el grupo de seguridad para Grafana (SSH y puerto 3000) en la VPC de Prometheus."""
    sg_name = f"{EC2_NAME_TAG}-SG"
    
    # 1. Intentar encontrar si el grupo ya existe en la VPC específica (Solución robusta)
    try:
        response = ec2.describe_security_groups(
            Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}, {'Name': 'group-name', 'Values': [sg_name]}]
        )
        sg_id = response['SecurityGroups'][0]['GroupId']
        print(f"  Grupo de Seguridad '{sg_name}' ya existe en VPC {vpc_id}. Reutilizando ID: {sg_id}")
        return sg_id
    except ClientError:
        pass 
    except IndexError:
        pass 

    # 2. Si no existe, crearlo
    try:
        sg_response = ec2.create_security_group(
            GroupName=sg_name,
            Description='SG para Grafana (SSH y puerto 3000)',
            VpcId=vpc_id
        )
        sg_id = sg_response['GroupId']
        print(f"  Grupo de Seguridad creado: {sg_id} en VPC {vpc_id}")

        # Reglas de entrada (Inbound)
        ec2.authorize_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[
                # SSH (puerto 22)
                {'IpProtocol': 'tcp', 'FromPort': 22, 'ToPort': 22, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
                # Grafana (puerto 3000)
                {'IpProtocol': 'tcp', 'FromPort': 3000, 'ToPort': 3000, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]}
            ]
        )
        return sg_id
    except ClientError as e:
        print(f"  Error al crear el Grupo de Seguridad: {e}")
        raise

def launch_grafana_instance(sg_id, subnet_id):
    """Lanza la instancia EC2 de Grafana en la Subnet de Prometheus, con el Rol de IAM para SSM."""
    print(f"--- 3. Lanzando instancia EC2 ({INSTANCE_TYPE}) en Subred {subnet_id} ---")

    try:
        run_instances_response = ec2.run_instances(
            ImageId=AMI_ID,
            InstanceType=INSTANCE_TYPE, 
            MinCount=1,
            MaxCount=1,
            KeyName=KEY_NAME,
            SecurityGroupIds=[sg_id],
            SubnetId=subnet_id,         
            UserData=GRAFANA_USER_DATA,
            IamInstanceProfile={'Name': SSM_INSTANCE_PROFILE_NAME},
            TagSpecifications=[
                {'ResourceType': 'instance', 'Tags': [{'Key': 'Name', 'Value': EC2_NAME_TAG}]}
            ]
        )
        instance_id = run_instances_response['Instances'][0]['InstanceId']
        print(f"  Instancia lanzada: {instance_id}. Esperando a que esté lista...")

        # Esperar a que la instancia esté en estado 'running'
        waiter = ec2.get_waiter('instance_running')
        waiter.wait(InstanceIds=[instance_id])
        
        # Obtener la IP pública
        ip_response = ec2.describe_instances(InstanceIds=[instance_id])
        public_ip = ip_response['Reservations'][0]['Instances'][0].get('PublicIpAddress')

        print(f"  Instancia ({instance_id}) lista. IP Pública: {public_ip}")
        return instance_id, public_ip

    except ClientError as e:
        print(f"  Error al lanzar la instancia EC2: {e}")
        raise

def configure_grafana_datasource(instance_id):
    """Ejecuta los comandos SSM para configurar la fuente de datos y la contraseña."""
    print("--- 4. Ejecutando Post-Configuración (Data Source y Contraseña) vía SSM ---")
    
    # Agregar un breve periodo de espera extra para asegurar que el agente SSM esté conectado, 
    # incluso después de que el estado sea 'running'
    print("  Esperando 30 segundos para que el Agente SSM se conecte...")
    time.sleep(30) 
    
    commands = [SSM_CONFIG_COMMANDS]
    
    try:
        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={'commands': commands},
            Comment='Configuración de Data Source de Prometheus y cambio de contraseña de Grafana'
        )
        command_id = response['Command']['CommandId']
        print(f"  Comando SSM enviado (ID: {command_id}). Esperando configuración (hasta 5m)...")
        
        waiter = ssm.get_waiter('command_executed')
        waiter.wait(CommandId=command_id, InstanceId=instance_id, WaiterConfig={'Delay': 30, 'MaxAttempts': 10}) 
        
        output = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
        
        if output['Status'] == 'Success':
            print("  ✅ Configuración de Grafana y Data Source completada con éxito.")
            return True
        else:
            print(f"  ❌ El comando SSM falló. (Estado: {output['Status']}).")
            print("  Salida Estándar:\n" + output.get('StandardOutputContent', 'N/A'))
            return False
            
    except Exception as e:
        print(f"  ❌ Error al ejecutar SSM o al esperar el resultado: {e}")
        return False

def main():
    print("El siguiente script automatiza el despliegue del servidor Grafana en la misma VPC que Prometheus.")
    # Muestra el diagrama del entorno 
    
    try:
        print("--- INICIO DE DESPLIEGUE DE GRAFANA ---")

        # 1. Obtener información de red de Prometheus
        vpc_id, subnet_id = get_prometheus_network_info(PROMETHEUS_INSTANCE_ID)
        
        # 2. Crear/Reutilizar Grupo de Seguridad en la VPC de Prometheus
        sg_id = create_security_group(vpc_id)
        
        # 3. Lanzar Instancia EC2 en la subred de Prometheus (con el Rol de IAM de SSM)
        instance_id, public_ip = launch_grafana_instance(sg_id, subnet_id)
        
        # 4. Configurar Fuente de Datos y Contraseña (SSM)
        if public_ip:
            if configure_grafana_datasource(instance_id):
                print("\n--- ✅ DESPLIEGUE COMPLETO Y EXITOSO. ---")
                print(f"  Accede a Grafana en: **http://{public_ip}:3000**")
                print(f"  Credenciales: Usuario: admin, Contraseña: {NEW_ADMIN_PASSWORD}")
            else:
                print("\n--- ❌ CONFIGURACIÓN SSM FALLIDA. Revisa el log de SSM. ---")
        else:
            print("\n--- ❌ DESPLIEGUE FALLIDO. No se pudo obtener la IP Pública. ---")
            
    except Exception as e:
        print(f"\n--- ❌ ERROR CRÍTICO EN EL DESPLIEGUE: {e} ---")

if __name__ == '__main__':
    main()
    

