aws ec2 terminate-instances --instance-ids $(aws ec2 describe-instances \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)
