$GSNAME = "GS-WEBMIN"

aws ec2 create-security-group \
    --description "Grupo de seguridad Webmin" \
    --group-name $GSNAME \


$GSID = (aws ec2 describe-security-groups \
    --group-names $GSNAME \
    --query "SecurityGroups[*].[GroupId]" \
    --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $GSID \
    --protocol tcp \
    --port 22 \
    --cidr 213.0.87.58/24

aws ec2 authorize-security-group-ingress \
    --group-id $GSID \
    --protocol tcp \
    --port 10000 \
    --cidr 0.0.0.0/0

aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --security-group-id $GSID \
    --instance-type t3.micro \
    --iam-instance-profile LabInstanceProfile \
    --key-name vockey