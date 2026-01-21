#!/bin/bash

set +e
REGION="us-east-1"
export AWS_DEFAULT_REGION=$REGION

echo "🔥 LIMPIANDO REGIÓN $REGION"

# ============================
# TRANSIT GATEWAYS
# ============================
echo "🧹 Eliminando Transit Gateways..."

TGWS=$(aws ec2 describe-transit-gateways \
  --query "TransitGateways[].TransitGatewayId" \
  --output text)

for TGW in $TGWS; do
  echo "➡️ TGW $TGW"

  ATTACHMENTS=$(aws ec2 describe-transit-gateway-attachments \
    --filters Name=transit-gateway-id,Values=$TGW \
    --query "TransitGatewayAttachments[].TransitGatewayAttachmentId" \
    --output text)

  for ATT in $ATTACHMENTS; do
    echo "   🧨 Attachment $ATT"
    aws ec2 delete-transit-gateway-vpc-attachment \
      --transit-gateway-attachment-id $ATT 2>/dev/null
  done

  echo "   ⏳ Esperando..."
  sleep 15

  aws ec2 delete-transit-gateway --transit-gateway-id $TGW 2>/dev/null
done

# ============================
# VPCS (NO DEFAULT)
# ============================
VPCS=$(aws ec2 describe-vpcs \
  --query "Vpcs[?IsDefault==\`false\`].VpcId" \
  --output text)

for VPC in $VPCS; do
  echo "➡️ VPC $VPC"

  # ---------- EC2 ----------
  INSTANCES=$(aws ec2 describe-instances \
    --filters Name=vpc-id,Values=$VPC \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

  if [ -n "$INSTANCES" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCES
    aws ec2 wait instance-terminated --instance-ids $INSTANCES
  fi

  # ---------- NAT GW ----------
  NATS=$(aws ec2 describe-nat-gateways \
    --filter Name=vpc-id,Values=$VPC \
    --query "NatGateways[].NatGatewayId" \
    --output text)

  for NAT in $NATS; do
    aws ec2 delete-nat-gateway --nat-gateway-id $NAT
  done

  sleep 15

  # ---------- IGW ----------
  IGWS=$(aws ec2 describe-internet-gateways \
    --filters Name=attachment.vpc-id,Values=$VPC \
    --query "InternetGateways[].InternetGatewayId" \
    --output text)

  for IGW in $IGWS; do
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW
  done

  # ---------- ROUTE TABLES ----------
  RTS=$(aws ec2 describe-route-tables \
    --filters Name=vpc-id,Values=$VPC \
    --query "RouteTables[].RouteTableId" \
    --output text)

  for RT in $RTS; do
    MAIN=$(aws ec2 describe-route-tables \
      --route-table-ids $RT \
      --query "RouteTables[0].Associations[?Main==\`true\`]" \
      --output text)

    if [ -n "$MAIN" ]; then
      continue
    fi

    ASSOCS=$(aws ec2 describe-route-tables \
      --route-table-ids $RT \
      --query "RouteTables[0].Associations[].RouteTableAssociationId" \
      --output text)

    for A in $ASSOCS; do
      aws ec2 disassociate-route-table --association-id $A
    done

    aws ec2 delete-route-table --route-table-id $RT
  done

  # ---------- SUBNETS ----------
  SUBNETS=$(aws ec2 describe-subnets \
    --filters Name=vpc-id,Values=$VPC \
    --query "Subnets[].SubnetId" \
    --output text)

  for S in $SUBNETS; do
    aws ec2 delete-subnet --subnet-id $S
  done

  # ---------- SECURITY GROUPS ----------
  SGS=$(aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values=$VPC \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text)

  for SG in $SGS; do
    aws ec2 delete-security-group --group-id $SG
  done

  # ---------- VPC ----------
  aws ec2 delete-vpc --vpc-id $VPC
  echo "✅ VPC $VPC eliminada"
done

echo "🎉 LIMPIEZA TERMINADA"
