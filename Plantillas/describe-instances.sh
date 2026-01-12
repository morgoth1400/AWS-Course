#Obtener IP pública de una instancia lanzada dado un ID
read -p "Proporciona el id de la instancia: " EC2
IP=$(aws ec2 describe-instances \
    --instance-ids $EC2 \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo $IP