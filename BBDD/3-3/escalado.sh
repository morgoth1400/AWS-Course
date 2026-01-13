#!/bin/bash
# CONFIGURACIÓN
DB_INSTANCE_ID="MI_INSTANCIA_RDS"
NEW_INSTANCE_CLASS="db.t3.medium"
SNAPSHOT_ID="snapshot-manual-$(date +%Y%m%d-%H%M)"


echo "LISTANDO TODAS LAS INSTANCIAS RDS (JSON)"
aws rds describe-db-instances


echo "LISTANDO TODAS LAS INSTANCIAS RDS (TABLA)"
aws rds describe-db-instances \
  --query "DBInstances[*].[DBInstanceIdentifier,Engine,DBInstanceClass,DBInstanceStatus,Endpoint.Address]" \
  --output table


echo "DETALLES COMPLETOS DE LA INSTANCIA: $DB_INSTANCE_ID"
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID"

echo "CREANDO SNAPSHOT MANUAL"
echo "Snapshot: $SNAPSHOT_ID"
aws rds create-db-snapshot \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --db-snapshot-identifier "$SNAPSHOT_ID"


echo "CAMBIANDO TIPO DE INSTANCIA (ESCALADO VERTICAL)"
echo "Nuevo tipo: $NEW_INSTANCE_CLASS"
aws rds modify-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --db-instance-class "$NEW_INSTANCE_CLASS" \
  --apply-immediately
