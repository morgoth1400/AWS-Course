#!/bin/bash
GSNAME="GS-WEBMIN"

EXISTING_SG=$(aws ec2 describe-security-groups \
    --group-names "$GSNAME" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null)

if [ "$EXISTING_SG" != "None" ] && [ -n "$EXISTING_SG" ]; then
    echo "Borrando Security Group existente: $EXISTING_SG"
    aws ec2 delete-security-group --group-id "$EXISTING_SG"

fi


aws ec2 create-security-group \
    --description "Grupo de seguridad Webmin" \
    --group-name $GSNAME


GSID=$(aws ec2 describe-security-groups \
    --group-names $GSNAME \
    --query "SecurityGroups[0].[GroupId]" \
    --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $GSID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $GSID \
    --protocol tcp \
    --port 10000 \
    --cidr 0.0.0.0/0


EC2_ID=$(aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --security-group-ids $GSID \
    --instance-type t3.micro \
    --iam-instance-profile Name=LabInstanceProfile \
    --key-name vockey \
    --user-data file://userdata.txt \
    --query 'Instances[*].InstanceId' --output text)

echo "Id de instancia EC2: " $EC2_ID

aws ec2 wait instance-running --instance-ids $EC2_ID

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$EC2_ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "IP de la EC2: " $PUBLIC_IP
echo "Acceso Webmin: "$PUBLIC_IP":10000"