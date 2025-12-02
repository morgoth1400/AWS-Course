# Obtén los IDs de las VPCs que tienen la etiqueta entorno=prueba
VPC_IDS=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=pruebas" \
    --query "Vpcs[*].VpcId" \
    --output text)
echo $VPC_ID



# Recorre cada ID de VPC y elimínala
for VPC_ID in $VPC_IDS; do
    echo "Eliminando VPC $VPC_ID..."
    
    # Eliminar recursos asociados (puentes de internet, subredes, etc.) antes de eliminar la VPC
    # Ejemplo: elimina subredes
    SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
    for SUBNET_ID in $SUBNET_IDS; do
        EC2_IDS=$(aws ec2 describe-instances \
            --filters "Name=subnet-id,Values=$SUBNET_ID" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text)    

            for EC2_ID in $EC2_IDS; do
                aws ec2 terminate-instances --instance-ids $EC2_ID
                echo "a"
                aws ec2 wait instance-terminated --instance-ids $EC2_ID
                echo "b"
            done


        aws ec2 delete-subnet --subnet-id $SUBNET_ID
        echo " Subnet $SUBNET_ID eliminada."
    done
    
    # (Opcional) Elimina más recursos aquí como Internet Gateways, Route Tables, etc., si existen
    
    # Elimina la VPC
    aws ec2 delete-vpc --vpc-id $VPC_ID
    echo "VPC $VPC_ID eliminada."
done
