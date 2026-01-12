#!/bin/bash

# CREACIÓN VPC
VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 192.168.0.0/16 \
        --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Dani-VPC}]' \
        --query Vpc.VpcId --output text)

echo "ID de la VPC: $VPC_ID"


# CREACIÓN PUERTA DE ENLACE (IGW)
IGW_ID=$(aws ec2 create-internet-gateway \
    --region us-east-1\
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=Dani-IGW}]' \
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


# CREACIÓN SUBRED CON ACCESO A INTERNET
SUB_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 192.168.0.0/20 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Dani-Subnet1}]' \
    --query Subnet.SubnetId --output text)

echo "ID de la subred:" $SUB_ID

aws ec2 modify-subnet-attribute --subnet-id $SUB_ID --map-public-ip-on-launch

echo "Habilitada asignación de IP pública en la subred $SUB_ID"


# CREACIÓN DE SUBRED SIN ACCESO A INTERNET
SUB_ID2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 192.168.16.0/20 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Dani-Subnet2}]' \
    --query Subnet.SubnetId --output text)

echo "ID de la subred:" $SUB_ID2



# CREACIÓN TABLA DE ENRUTAMIENTO
RT_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Dani-RT}]'\
    --query RouteTable.RouteTableId --output text) > /dev/null

# ASOCIACIÓN DE LA TABLA DE ENRUTAMIENTO A UNA SUBRED
ATTACH_STATE=$(aws ec2 associate-route-table \
    --route-table-id $RT_ID \
    --subnet-id $SUB_ID \
    --query "AssociationState.State" \
    --output text)

echo "Asociada la tabla de enrutamiento $RT_ID con la subred $SUB_ID. Estado: $ATTACH_STATE"

# REDIRECCIÓN DE TODO EL TRÁFICO AL IGW
aws ec2 create-route --route-table-id $RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID
        
echo "ID de la tabla de enrutamiento: $RT_ID"


# CREACIÓN  GRUPO DE SEGURIDAD
SG=$(aws ec2 create-security-group --group-name My-SG \
    --description "SSH+HTTP+HTTPS" \
    --vpc-id $VPC_ID \
    --output text)

SG_ID=$(echo "$SG" | awk '{print $1}')
SG_ARN=$(echo "$SG" | awk '{print $0}')

echo "ID del grupo de seguridad: $SG_ID"
echo "ARN del grupo de seguridad: $SG_ID_ARN"

# HABILITAMOS LOS PUERTOS EN EL GRUPO DE SEGURIDAD (22, 80, 443)
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 > /dev/null

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 > /dev/null

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 > /dev/null

echo "Habilitados los puertos 22, 80 y 443 para el grupo de seguridad $SG_ID"


# CREACIÓN DE UNA INSTANCIA EC2 CON CONEXIÓN A INTERNET
EC2_ID=$(aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --instance-type t2.micro \
    --subnet-id $SUB_ID \
    --security-group-ids $SG_ID \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Dani-Ubuntu}]' \
    --query 'Instances[*].InstanceId' --output text)
    #--private-ip-address 192.168.0.100 \

aws ec2 wait instance-running --instance-ids $EC2_ID

echo "ID de la instancia con acceso a internet: $EC2_ID"



# CREACIÓN DE UNA INSTANCIA EC2 SIN CONEXIÓN A INTERNET
EC2_ID=$(aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --instance-type t2.micro \
    --subnet-id $SUB_ID2 \
    --security-group-ids $SG_ID \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=NO-INTERNET}]' \
    --query 'Instances[*].InstanceId' --output text)
    #--private-ip-address 192.168.0.100 \

aws ec2 wait instance-running --instance-ids $EC2_ID

echo "ID de la instancia sin internet: $EC2_ID"

## ASIGNACIÓN POSTERIOR - GRUPO DE SEGURIDAD (OPCIONAL)
# aws ec2 modify-instance-attribute \
#     --instance-id $EC2_ID \
#     --groups $SG_ID
            # Es únicamente en caso de no haber indicado previamente el grupo de
            # de seguridad durante la creación de la instancia.