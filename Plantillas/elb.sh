#!/bin/bash

SG_ID=$(aws ec2 describe-security-groups \
        --group-names GS-WebServer \
        --query "SecurityGroups[*].{Id:GroupId}" --output text
)

VPC_ID=$(aws ec2 describe-vpcs \
        --query "Vpcs[0].VpcId" \
        --output text
)

SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --query "Subnets[0].SubnetId" \
        --output text
)


BLUE_ID=$(aws ec2 run-instances \
        --image-id ami-0fa3fe0fa7920f68e \
        --instance-type t2.micro \
        --security-group-ids $SG_ID \
        --associate-public-ip-address \
        --count 1 \
        --key-name vockey \
        --subnet-id $SUBNET_ID \
        --user-data "file://./userdataB.txt" \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Blue}]' \
        --query 'Instances[*].InstanceId' --output text
)

echo "ID de la instancia Blue: " $BLUE_ID

aws ec2 wait instance-running \
        --instance-ids $BLUE_ID

GREEN_ID=$(aws ec2 run-instances \
        --image-id ami-0fa3fe0fa7920f68e \
        --instance-type t2.micro \
        --security-group-ids $SG_ID \
        --associate-public-ip-address \
        --count 1 \
        --key-name vockey \
        --subnet-id $SUBNET_ID \
        --user-data "file://./userdataG.txt" \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Green}]' \
        --query 'Instances[*].InstanceId' --output text
)

echo "ID de la instancia Green: " $GREEN_ID

aws ec2 wait instance-running \
        --instance-ids $GREEN_ID

sleep 15


TG_ARN=$(aws elbv2 create-target-group \
        --name tg-script\
        --protocol TCP \
        --port 80 \
        --vpc-id $VPC_ID \
        --target-type instance \
        --query "TargetGroups[0].TargetGroupArn" --output text
)

aws elbv2 register-targets \
        --target-group-arn $TG_ARN \
        --targets Id=$BLUE_ID Id=$GREEN_ID

ELB_ARN=$(aws elbv2 create-load-balancer \
        --name elb-script \
        --type network \
        --subnets $SUBNET_ID \
        --security-groups $SG_ID \
        --scheme internet-facing \
        --query "LoadBalancers[0].LoadBalancerArn" --output text)

aws elbv2 create-listener \
        --load-balancer-arn $ELB_ARN \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=$TG_ARN

DNS_NAME=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ELB_ARN \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "DNS del NLB: $DNS_NAME"






