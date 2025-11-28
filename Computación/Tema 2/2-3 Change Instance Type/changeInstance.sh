#!/bin/bash
# EC2_ID=$(aws ec2 run-instances \
#     --image-id ami-0ecb62995f68bb549 \
#     --instance-type t3.micro \
#     --iam-instance-profile Name=LabInstanceProfile \
#     --key-name vockey \
#     --query 'Instances[*].InstanceId' --output text)

# echo "Instancia" $EC2_ID "lanzada."

# aws ec2 wait instance-running --instance-ids $EC2_ID --output text > /dev/null

EC2_ID=$1
EC2_TYPE=$2

# Comprobación de parámetros vacíos
if [ -z "$EC2_ID" ]; then
    echo "Error: no se ha proporcionado el Instance ID."
    echo "Uso: $0 <instance-id> <instance-type>"
    exit 1
fi

if [ -z "$EC2_TYPE" ]; then
    echo "Error: no se ha proporcionado el Instance Type."
    echo "Uso: $0 <instance-id> <instance-type>"
    exit 1
fi


# Comprobación de tipo de instancia válido
validate_ec2_type() { 
    local TYPE=$1
    
    if ! aws ec2 describe-instance-types \
        --instance-types "$TYPE" \
        --output text > /dev/null 2>&1; then
        echo "Error: el tipo de instancia '$TYPE' no es válido en AWS."
        return 1
    fi

    return 0
 }

if ! validate_ec2_type "$EC2_TYPE"; then
    exit 1
fi

# ¿Existe la instancia? Si no existe, se para la ejecución del script.
EXISTS=$(aws ec2 describe-instances \
    --instance-ids "$EC2_ID" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

if [ -z "$EXISTS" ]; then
    echo "La instancia $EC2_ID NO existe. Abortando ejecución."
    exit 1
else
    echo "La instancia $EXISTS existe"
fi


CURRENT_TYPE=$(aws ec2 describe-instances \
    --instance-ids "$EC2_ID" \
    --query "Reservations[0].Instances[0].InstanceType" \
    --output text )

if [[ "$EC2_TYPE" == "$CURRENT_TYPE" ]]; then
    echo "La instancia ya es de tipo '$EC2_TYPE'"

    while true; do
        read -p "¿Desea proporcionar otro tipo de instancia? [S/N]: " respuesta

        case "$respuesta" in
            [Ss])
                read -p "Ok, introduzca el nuevo tipo: " NEW_TYPE
                if [[ "$NEW_TYPE" == "$CURRENT_TYPE" ]]; then
                    echo "El tipo introducido es igual al actual. Debe elegir uno diferente."
                    continue
                fi

                if ! validate_ec2_type "$NEW_TYPE"; then
                    continue
                fi

                EC2_TYPE="$NEW_TYPE"
                break
                ;;
            [Nn])
                echo "Abortando script..."
                exit 1
                ;;
            *)
                echo "Respuesta inválida. Debe ser S o N."
                ;;
        esac
    done
fi



# ¿Está en estado 'running'? En caso de que sí, se para la instancia.
RUNNING=$(aws ec2 describe-instances \
    --instance-ids "$EC2_ID" \
    --query "Reservations[*].Instances[?State.Name=='running'].InstanceId" \
    --output text)



if [ -z "$RUNNING" ]; then
    echo "La instancia $EC2_ID ya está parada"
else
    while true; do
        read -p "La instancia $EC2_ID será parada. ¿Desea continuar? [S/N] => " respuesta

        case "$respuesta" in
            [Ss])
                break
                ;;
            [Nn])
                echo "Abortando script..."
                exit 1
                ;;
            *)
                echo "Respuesta inválida. Debe ser S o N."
                ;;
        esac
    done

    aws ec2 stop-instances --instance-ids $EC2_ID --output text > /dev/null

    echo "La instancia $EC2_ID se está parando"

    aws ec2 wait instance-stopped --instance-ids $EC2_ID

    echo "La instancia $EC2_ID está en estado 'stopped'"
fi

# Se modifica el tipo de instancia
aws ec2 modify-instance-attribute \
    --instance-id $EC2_ID \
    --instance-type Value=$EC2_TYPE

echo "Se ha  modificado el tipo de instancia"

aws ec2 start-instances --instance-ids $EC2_ID --output text > /dev/null

echo "Se está lanzando la instancia $EC2_ID"

aws ec2 wait instance-running --instance-ids $EC2_ID

echo "Se ha lanzado la instancia $EC2_ID de tipo $EC2_TYPE"



