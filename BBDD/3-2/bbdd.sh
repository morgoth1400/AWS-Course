#!/bin/bash
set -e

echo "Iniciando limpieza de recursos previos..."

### VARIABLES
EC2_NAME="Windows-Server-2025"
RDS_ID="mysql-db"
EC2_SG_NAME="ec2-windows-sg"
RDS_SG_NAME="rds-mysql-sg"
KEY_NAME="vockey"
DB_NAME="appdb"
DB_USER="admin"
DB_PASSWORD="Juande123"
INSTANCE_TYPE="t3.large"   # 8 GB RAM

### OBTENER VPC POR DEFECTO
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)

echo "VPC por defecto: $VPC_ID"

###BORRAR RDS SI YA EXISTE
if aws rds describe-db-instances \
  --db-instance-identifier $RDS_ID >/dev/null 2>&1; then

  echo "Eliminando RDS $RDS_ID..."
  aws rds delete-db-instance \
    --db-instance-identifier $RDS_ID \
    --skip-final-snapshot

  aws rds wait db-instance-deleted \
    --db-instance-identifier $RDS_ID
fi

###TERMINAR EC2 SI YA EXISTE
EC2_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$EC2_NAME" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

if [ -n "$EC2_ID" ]; then
  echo "Terminando EC2 $EC2_ID..."
  aws ec2 terminate-instances --instance-ids $EC2_ID
  aws ec2 wait instance-terminated --instance-ids $EC2_ID
fi

###BORRAR SG EC2
EC2_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$EC2_SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ "$EC2_SG_ID" != "None" ] && [ -n "$EC2_SG_ID" ]; then
  echo "🗑️ Eliminando SG EC2 $EC2_SG_ID..."
  aws ec2 delete-security-group --group-id $EC2_SG_ID
fi

###BORRAR SG RDS
RDS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$RDS_SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ "$RDS_SG_ID" != "None" ] && [ -n "$RDS_SG_ID" ]; then
  echo "🗑️ Eliminando SG RDS $RDS_SG_ID..."
  aws ec2 delete-security-group --group-id $RDS_SG_ID
fi

echo "Limpieza finalizada"

echo "Creando infraestructura..."

###SG EC2 (RDP)
EC2_SG_ID=$(aws ec2 create-security-group \
  --group-name $EC2_SG_NAME \
  --description "RDP access" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $EC2_SG_ID \
  --protocol tcp \
  --port 3389 \
  --cidr 0.0.0.0/0

echo "SG EC2 creado: $EC2_SG_ID"

###OBTENER AMI WINDOWS SERVER 2025
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=Windows_Server-2025-English-Full-Base*" \
  --query 'Images | sort_by(@, &CreationDate)[-1].ImageId' \
  --output text)

echo "AMI Windows Server 2025: $AMI_ID"

###CREAR EC2 WINDOWS
EC2_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $EC2_SG_ID \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2_NAME}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "EC2 creada: $EC2_ID"

aws ec2 wait instance-running --instance-ids $EC2_ID

###SG RDS (solo EC2)
RDS_SG_ID=$(aws ec2 create-security-group \
  --group-name $RDS_SG_NAME \
  --description "MySQL access from EC2 only" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group $EC2_SG_ID

echo "SG RDS creado: $RDS_SG_ID"

###CREAR RDS MYSQL
aws rds create-db-instance \
  --db-instance-identifier $RDS_ID \
  --allocated-storage 20 \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username $DB_USER \
  --master-user-password $DB_PASSWORD \
  --vpc-security-group-ids $RDS_SG_ID \
  --db-name $DB_NAME \
  --backup-retention-period 7 \
  --no-publicly-accessible

echo "RDS MySQL creada: $RDS_ID"
