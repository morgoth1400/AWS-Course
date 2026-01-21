import boto3

ec2 = boto3.client("ec2")

# ======================
# 1. Crear VPC
# ======================
vpc = ec2.create_vpc(
    CidrBlock="10.0.0.0/16"
)

vpc_id = vpc["Vpc"]["VpcId"]
print(f"VPC creada: {vpc_id}")

ec2.modify_vpc_attribute(
    VpcId=vpc_id,
    EnableDnsSupport={"Value": True}
)

ec2.modify_vpc_attribute(
    VpcId=vpc_id,
    EnableDnsHostnames={"Value": True}
)

# ======================
# 2. Crear subred pública
# ======================
public_subnet = ec2.create_subnet(
    VpcId=vpc_id,
    CidrBlock="10.0.1.0/24"
)

public_subnet_id = public_subnet["Subnet"]["SubnetId"]
print(f"Subred pública: {public_subnet_id}")

# ======================
# 3. Crear subred privada
# ======================
private_subnet = ec2.create_subnet(
    VpcId=vpc_id,
    CidrBlock="10.0.2.0/24"
)

private_subnet_id = private_subnet["Subnet"]["SubnetId"]
print(f"Subred privada: {private_subnet_id}")

# ======================
# 4. Internet Gateway
# ======================
igw = ec2.create_internet_gateway()
igw_id = igw["InternetGateway"]["InternetGatewayId"]

ec2.attach_internet_gateway(
    InternetGatewayId=igw_id,
    VpcId=vpc_id
)

print(f"Internet Gateway: {igw_id}")

# ======================
# 5. Tabla de rutas pública
# ======================
route_table = ec2.create_route_table(VpcId=vpc_id)
route_table_id = route_table["RouteTable"]["RouteTableId"]

ec2.create_route(
    RouteTableId=route_table_id,
    DestinationCidrBlock="0.0.0.0/0",
    GatewayId=igw_id
)

ec2.associate_route_table(
    RouteTableId=route_table_id,
    SubnetId=public_subnet_id
)

# ======================
# 6. NACL pública
# ======================
public_nacl = ec2.create_network_acl(VpcId=vpc_id)
public_nacl_id = public_nacl["NetworkAcl"]["NetworkAclId"]

# Asociar a subred pública
ec2.associate_network_acl(
    NetworkAclId=public_nacl_id,
    SubnetId=public_subnet_id
)

# HTTP
ec2.create_network_acl_entry(
    NetworkAclId=public_nacl_id,
    RuleNumber=100,
    Protocol="6",  # TCP
    RuleAction="allow",
    Egress=False,
    CidrBlock="0.0.0.0/0",
    PortRange={"From": 80, "To": 80}
)

# HTTPS
ec2.create_network_acl_entry(
    NetworkAclId=public_nacl_id,
    RuleNumber=110,
    Protocol="6",
    RuleAction="allow",
    Egress=False,
    CidrBlock="0.0.0.0/0",
    PortRange={"From": 443, "To": 443}
)

# Salida permitida
ec2.create_network_acl_entry(
    NetworkAclId=public_nacl_id,
    RuleNumber=100,
    Protocol="-1",
    RuleAction="allow",
    Egress=True,
    CidrBlock="0.0.0.0/0"
)

print("NACL pública configurada")

# ======================
# 7. NACL privada
# ======================
private_nacl = ec2.create_network_acl(VpcId=vpc_id)
private_nacl_id = private_nacl["NetworkAcl"]["NetworkAclId"]

ec2.associate_network_acl(
    NetworkAclId=private_nacl_id,
    SubnetId=private_subnet_id
)

# Permitir tráfico desde la subred pública
ec2.create_network_acl_entry(
    NetworkAclId=private_nacl_id,
    RuleNumber=100,
    Protocol="-1",
    RuleAction="allow",
    Egress=False,
    CidrBlock="10.0.1.0/24"
)

# Permitir salida hacia la subred pública
ec2.create_network_acl_entry(
    NetworkAclId=private_nacl_id,
    RuleNumber=100,
    Protocol="-1",
    RuleAction="allow",
    Egress=True,
    CidrBlock="10.0.1.0/24"
)

print("NACL privada configurada")

print("Escenario creado correctamente")
