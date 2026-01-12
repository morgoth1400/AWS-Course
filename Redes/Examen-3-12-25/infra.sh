#!/bin/bash

# CREACIÓN VPC
VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.10.0.0/16 \
        --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Examen-VPC}]' \
        --query Vpc.VpcId --output text)

echo "ID de la VPC: $VPC_ID"


# CREACIÓN PUERTA DE ENLACE (IGW)
IGW_ID=$(aws ec2 create-internet-gateway \
    --region us-east-1\
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=Examen-IGW}]' \
    --query InternetGateway.InternetGatewayId --output text)


# ASIGNACIÓN PUERTA DE ENLACE-VPC
aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID

# HABILITAMOS EL DNS EN LA VPC
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames "{\"Value\":true}"

echo "El ID del IGW es: $IGW_ID"

############SUBNETS#################
# CREACIÓN SUBRED PÚBLICA 1
PUB_SUBNET1_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.10.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1-examen}]' \
    --query Subnet.SubnetId --output text)

echo "ID de la subred:" $PUB_SUBNET1_ID

aws ec2 modify-subnet-attribute --subnet-id $PUB_SUBNET1_ID --map-public-ip-on-launch

echo "Habilitada asignación de IP pública en la subred $PUB_SUBNET1_ID"

# CREACIÓN SUBRED PÚBLICA 2
PUB_SUBNET2_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.10.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-2-examen}]' \
    --query Subnet.SubnetId --output text)

echo "ID de la subred:" $PUB_SUBNET2_ID

aws ec2 modify-subnet-attribute --subnet-id $PUB_SUBNET2_ID --map-public-ip-on-launch

echo "Habilitada asignación de IP pública en la subred $PUB_SUBNET2_ID"

# CREACIÓN SUBRED PRIVADA 1
PRIV_SUBNET1_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.10.3.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1-examen}]' \
    --query Subnet.SubnetId --output text)

echo "ID de la subred privada:" $PRIV_SUBNET1_ID


# CREACIÓN SUBRED PRIVADA 2
PRIV_SUBNET2_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.10.4.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-2-examen}]' \
    --query Subnet.SubnetId --output text)

echo "ID de la subred privada:" $PRIV_SUBNET2_ID


###########ROUTETABLES##################
# CREACIÓN TABLA DE ENRUTAMIENTO PÚBLICA 1
PUB_RT1_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=PUB-RT1}]'\
    --query RouteTable.RouteTableId --output text) > /dev/null

# REDIRECCIÓN DE TODO EL TRÁFICO AL IGW
aws ec2 create-route --route-table-id $PUB_RT1_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID
        
echo "ID de la tabla de enrutamiento pública: $PUB_RT1_ID"

# ASOCIACIÓN DE LA TABLA DE ENRUTAMIENTO
ATTACH_STATE=$(aws ec2 associate-route-table \
    --route-table-id $PUB_RT1_ID \
    --subnet-id $PUB_SUBNET1_ID \
    --query "AssociationState.State" \
    --output text)

echo "Asociada la tabla de enrutamiento $PUB_RT1_ID con la subred $PUB_SUBNET1_ID. Estado: $ATTACH_STATE"


# CREACIÓN TABLA DE ENRUTAMIENTO PÚBLICA 2
PUB_RT2_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=PUB-RT2}]'\
    --query RouteTable.RouteTableId --output text) > /dev/null

# REDIRECCIÓN DE TODO EL TRÁFICO AL IGW
aws ec2 create-route --route-table-id $PUB_RT2_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID
        
echo "ID de la tabla de enrutamiento pública: $PUB_RT2_ID"

# ASOCIACIÓN DE LA TABLA DE ENRUTAMIENTO
ATTACH_STATE=$(aws ec2 associate-route-table \
    --route-table-id $PUB_RT2_ID \
    --subnet-id $PUB_SUBNET2_ID \
    --query "AssociationState.State" \
    --output text)

echo "Asociada la tabla de enrutamiento $PUB_RT2_ID con la subred $PUB_SUBNET2_ID. Estado: $ATTACH_STATE"


# NAT GATEWAY
EIP_ALLOC_ID=$(aws ec2 allocate-address \
    --query "AllocationId" \
    --output text)

echo "Elastic IP allocation: $EIP_ALLOC_ID"

NAT_GW_ID=$(aws ec2 create-nat-gateway \
    --subnet-id $PUB_SUBNET1_ID \
    --allocation-id $EIP_ALLOC_ID \
    --query "NatGateway.NatGatewayId" \
    --output text)

echo "NAT Gateway $NAT_GW_ID en $PUB_SUBNET1_ID"

# ESPERAMOS A QUE EL NATGW ESTÉ DISPONIBLE
aws ec2 wait nat-gateway-available \
    --nat-gateway-ids $NAT_GW_ID

# TABLA DE RUTAS PRIVADA 1
PRIV_RT1_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query "RouteTable.RouteTableId" \
    --output text)

echo "Tabla de rutas privada: $PRIV_RT1_ID"

# RUTA HACIA INTERNET USANDO NAT
aws ec2 create-route \
    --route-table-id $PRIV_RT1_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW_ID

# ASOCIAR A SUBREDES PRIVADAS
ATTACH_STATE=$(aws ec2 associate-route-table \
    --route-table-id $PRIV_RT1_ID \
    --subnet-id $PRIV_SUBNET1_ID \
    --query "AssociationState.State" \
    --output text)

echo "Asociada la tabla de enrutamiento $PRIV_RT1_ID con la subred $PRIV_SUBNET1_ID. Estado: $ATTACH_STATE"

# TABLA DE RUTAS PRIVADA 2
PRIV_RT2_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query "RouteTable.RouteTableId" \
    --output text)

echo "Tabla de rutas privada: $PRIV_RT2_ID"

# RUTA HACIA INTERNET USANDO NAT
aws ec2 create-route \
    --route-table-id $PRIV_RT2_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW_ID

# ASOCIAR A SUBREDES PRIVADAS
ATTACH_STATE=$(aws ec2 associate-route-table \
    --route-table-id $PRIV_RT2_ID \
    --subnet-id $PRIV_SUBNET2_ID \
    --query "AssociationState.State" \
    --output text)

echo "Asociada la tabla de enrutamiento $PRIV_RT2_ID con la subred $PRIV_SUBNET2_ID. Estado: $ATTACH_STATE"


##########GRUPOS DE SEGURIDAD#############
# GRUPO DE SEGURIDAD EC2 PÚBLICAS
PUB_SG=$(aws ec2 create-security-group --group-name Public-SG \
    --description "SSH" \
    --vpc-id $VPC_ID \
    --output text)

PUB_SG_ID=$(echo "$PUB_SG" | awk '{print $1}')
PUB_SG_ARN=$(echo "$PUB_SG" | awk '{print $0}')

echo "ID del grupo de seguridad: $PUB_SG_ID"
echo "ARN del grupo de seguridad: $PUB_SG_ARN"

# HABILITAMOS EL PUERTO 22 EN EL GRUPO DE SEGURIDAD (22)
aws ec2 authorize-security-group-ingress \
    --group-id $PUB_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 > /dev/null \
    --output text


echo "Habilitado el puerto 22 para el grupo de seguridad $PUB_SG_ID"

# GRUPO DE SEGURIDAD EC2 PRIVADAS (SOLO SE PUEDE ACCEDER DESDE 'Public-SG')
PRIV_SG=$(aws ec2 create-security-group --group-name Private-SG \
    --description "SSH(Public-SG)" \
    --vpc-id $VPC_ID \
    --output text)

PRIV_SG_ID=$(echo "$PRIV_SG" | awk '{print $1}')
PRIV_SG_ARN=$(echo "$PRIV_SG" | awk '{print $0}')

echo "ID del grupo de seguridad: $PRIV_SG_ID"
echo "ARN del grupo de seguridad: $PRIV_SG_ARN"

# HABILITAMOS EL PUERTO 22 EN EL GRUPO DE SEGURIDAD (22)
aws ec2 authorize-security-group-ingress \
    --group-id $PRIV_SG_ID \
    --protocol tcp \
    --port 22 \
    --source-group $PUB_SG_ID \
    --output text


echo "Habilitado el puerto 22 para el grupo de seguridad $PRIV_SG_ID"

################ NACLS #####################
PUB_NACL_ID=$(aws ec2 create-network-acl \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=PublicNACL}]' \
    --query 'NetworkAcl.NetworkAclId' --output text)

PRIV_NACL_ID=$(aws ec2 create-network-acl \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=PrivateNACL}]' \
    --query 'NetworkAcl.NetworkAclId' --output text)

# SUBNETS PUBLICAS
ASSOC1_ID=$(aws ec2 describe-network-acls \
   --filters Name=association.subnet-id,Values=$PUB_SUBNET1_ID \
   --query "NetworkAcls[0].Associations[0].NetworkAclAssociationId" \
   --output text)
aws ec2 replace-network-acl-association \
    --association-id $ASSOC1_ID \
    --network-acl-id $PUB_NACL_ID \
    --output text

ASSOC2_ID=$(aws ec2 describe-network-acls \
   --filters Name=association.subnet-id,Values=$PUB_SUBNET2_ID \
   --query "NetworkAcls[0].Associations[0].NetworkAclAssociationId" \
   --output text)

aws ec2 replace-network-acl-association \
    --association-id $ASSOC2_ID \
    --network-acl-id $PUB_NACL_ID \
    --output text

# SUBNETS PRIVADAS
ASSOC1_ID=$(aws ec2 describe-network-acls \
   --filters Name=association.subnet-id,Values=$PRIV_SUBNET1_ID \
   --query "NetworkAcls[0].Associations[0].NetworkAclAssociationId" \
   --output text)
aws ec2 replace-network-acl-association \
    --association-id $ASSOC1_ID \
    --network-acl-id $PRIV_NACL_ID \
    --output text

ASSOC2_ID=$(aws ec2 describe-network-acls \
   --filters Name=association.subnet-id,Values=$PRIV_SUBNET2_ID \
   --query "NetworkAcls[0].Associations[0].NetworkAclAssociationId" \
   --output text)

aws ec2 replace-network-acl-association \
    --association-id $ASSOC2_ID \
    --network-acl-id $PRIV_NACL_ID \
    --output text

# CONFIGURACIÓN NACL PÚBLICA
# BORRA REGLAS POR DEFECTO
aws ec2 delete-network-acl-entry --network-acl-id $PUB_NACL_ID --rule-number 100 --ingress --output text > /dev/null
aws ec2 delete-network-acl-entry --network-acl-id $PUB_NACL_ID --rule-number 100 --egress --output text > /dev/null
# HTTP (80)
aws ec2 create-network-acl-entry \
    --network-acl-id $PUB_NACL_ID \
    --ingress \
    --rule-number 100 \
    --protocol tcp \
    --rule-action allow \
    --cidr-block 0.0.0.0/0 \
    --port-range From=80,To=80

# HTTPS (443)
aws ec2 create-network-acl-entry \
    --network-acl-id $PUB_NACL_ID \
    --ingress \
    --rule-number 110 \
    --protocol tcp \
    --rule-action allow \
    --cidr-block 0.0.0.0/0 \
    --port-range From=443,To=443

# SSH (22)
aws ec2 create-network-acl-entry \
    --network-acl-id $PUB_NACL_ID \
    --ingress \
    --rule-number 120 \
    --protocol tcp \
    --rule-action allow \
    --cidr-block 0.0.0.0/0 \
    --port-range From=22,To=22

# PERMITIR RESPUESTAS
aws ec2 create-network-acl-entry \
    --network-acl-id $PUB_NACL_ID \
    --ingress \
    --rule-number 130 \
    --protocol tcp \
    --rule-action allow \
    --cidr-block 0.0.0.0/0 \
    --port-range From=1024,To=65535
# aws ec2 create-network-acl-entry \
#     --network-acl-id $PUB_NACL_ID \
#     --egress \
#     --rule-number 110 \
#     --protocol tcp \
#     --rule-action allow \
#     --cidr-block 0.0.0.0/0 \
#     --port-range From=1024,To=65535


# DENEGAR EL RESTO
aws ec2 create-network-acl-entry \
    --network-acl-id $PUB_NACL_ID \
    --ingress \
    --rule-number 200 \
    --protocol -1 \
    --rule-action deny \
    --cidr-block 0.0.0.0/0

# PERMITIR TRÁFICO DE SALIDA
aws ec2 create-network-acl-entry \
    --network-acl-id $PUB_NACL_ID \
    --egress \
    --rule-number 100 \
    --protocol -1 \
    --rule-action allow \
    --cidr-block 0.0.0.0/0


# CONFIGURACIÓN NACL PRIVADA
# BORRA REGLAS POR DEFECTO
aws ec2 delete-network-acl-entry --network-acl-id $PRIV_NACL_ID --rule-number 100 --ingress --output text > /dev/null
aws ec2 delete-network-acl-entry --network-acl-id $PRIV_NACL_ID --rule-number 100 --egress --output text > /dev/null

# PERMITIR TRÁFICO INTERNO VPC
aws ec2 create-network-acl-entry \
    --network-acl-id $PRIV_NACL_ID \
    --ingress \
    --rule-number 100 \
    --protocol -1 \
    --rule-action allow \
    --cidr-block 10.10.0.0/16

# DENEGAR TRÁFICO EXTERNO
aws ec2 create-network-acl-entry \
    --network-acl-id $PRIV_NACL_ID \
    --ingress \
    --rule-number 200 \
    --protocol -1 \
    --rule-action deny \
    --cidr-block 0.0.0.0/0

# PERMITIR SALIDA (PARA USAR NATGW)
aws ec2 create-network-acl-entry \
    --network-acl-id $PRIV_NACL_ID \
    --egress \
    --rule-number 100 \
    --protocol -1 \
    --rule-action allow \
    --cidr-block 0.0.0.0/0

aws ec2 create-network-acl-entry \
    --network-acl-id $PRIV_NACL_ID \
    --egress \
    --rule-number 110 \
    --protocol tcp \
    --rule-action allow \
    --cidr-block 0.0.0.0/0 \
    --port-range From=1024,To=65535



# CREACIÓN DE UNA INSTANCIA EC2 EN PUB_SUBNET1
EC2_PUB1_ID=$(aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --instance-type t2.micro \
    --subnet-id $PUB_SUBNET1_ID \
    --security-group-ids $PUB_SG_ID \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=PUB1}]' \
    --query 'Instances[*].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids $EC2_PUB1_ID

echo "ID de la instancia con acceso a internet: $EC2_PUB1_ID"

 
# CREACIÓN DE UNA INSTANCIA EC2 EN PUB_SUBNET2
EC2_PUB2_ID=$(aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --instance-type t2.micro \
    --subnet-id $PUB_SUBNET2_ID \
    --security-group-ids $PUB_SG_ID \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=PUB2}]' \
    --query 'Instances[*].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids $EC2_PUB2_ID

echo "ID de la instancia con acceso a internet: $EC2_PUB2_ID"



# CREACIÓN DE UNA INSTANCIA EC2 EN PRIV_SUBNET1
EC2_PRIV1_ID=$(aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --instance-type t2.micro \
    --subnet-id $PRIV_SUBNET1_ID \
    --security-group-ids $PRIV_SG_ID \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=PRIV1}]' \
    --query 'Instances[*].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids $EC2_PRIV1_ID

echo "ID de la instancia con acceso a internet: $EC2_PRIV1_ID"



# CREACIÓN DE UNA INSTANCIA EC2 PRIV_SUBNET2
EC2_PRIV2_ID=$(aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --instance-type t2.micro \
    --subnet-id $PRIV_SUBNET2_ID \
    --security-group-ids $PRIV_SG_ID \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=PRIV2}]' \
    --query 'Instances[*].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids $EC2_PRIV2_ID

echo "ID de la instancia con acceso a internet: $EC2_PRIV2_ID"

