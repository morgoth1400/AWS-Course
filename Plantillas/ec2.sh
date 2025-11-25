SG_ID=$(aws ec2 describe-security-groups \
        --group-names GS-WebServer \
        --query "SecurityGroups[*].{Id:GroupId}" --output text
)


EC2_ID=$(aws ec2 run-instances \
        --image-id ami-0fa3fe0fa7920f68e \
        --instance-type t2.micro \
        --security-group-ids $SG_ID \
        --associate-public-ip-address \
        --count 1 \
        --key-name vockey \
        --user-data "file://./userdata.txt" \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Blue}]' \
        --query 'Instances[*].InstanceId' --output text)

echo "ID de la instancia: " $EC2_ID
