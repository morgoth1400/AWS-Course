VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/24 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=pruebas}]' \
    --query 'Vpc.VpcId' \
    --output text)


SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.0.0/25 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-1a}]' \
    --query 'Subnet.SubnetId' \
    --output text)



EC2_ID=$(aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUBNET_ID \
    --output text \
    --query 'Instances[*].InstanceId')

echo "Instancia $EC2_ID corriendo en subnet pública $SUBNET_ID de VPC $VPC_ID"