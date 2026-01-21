import boto3
import time

REGION = "us-east-1"
KEY_NAME = "vockey"
AMI = "ami-0c02fb55956c7d316"  # Ubuntu
INSTANCE_TYPE = "t2.micro"

ec2 = boto3.client("ec2", region_name=REGION)

def wait_instance(instance_id):
    ec2.get_waiter("instance_running").wait(InstanceIds=[instance_id])

print("\n=== CREANDO VPC ===")
vpc = ec2.create_vpc(CidrBlock="15.0.0.0/20")["Vpc"]["VpcId"]
ec2.modify_vpc_attribute(VpcId=vpc, EnableDnsSupport={"Value": True})
ec2.modify_vpc_attribute(VpcId=vpc, EnableDnsHostnames={"Value": True})
print(f"[+] VPC {vpc}")

print("\n=== SUBREDES ===")
subnet_public = ec2.create_subnet(VpcId=vpc, CidrBlock="15.0.1.0/24")["Subnet"]["SubnetId"]
subnet_backend = ec2.create_subnet(VpcId=vpc, CidrBlock="15.0.2.0/24")["Subnet"]["SubnetId"]
subnet_db = ec2.create_subnet(VpcId=vpc, CidrBlock="15.0.3.0/24")["Subnet"]["SubnetId"]

print("\n=== INTERNET GATEWAY ===")
igw = ec2.create_internet_gateway()["InternetGateway"]["InternetGatewayId"]
ec2.attach_internet_gateway(VpcId=vpc, InternetGatewayId=igw)

print("\n=== NAT GATEWAY ===")
eip = ec2.allocate_address(Domain="vpc")["AllocationId"]

nat = ec2.create_nat_gateway(
    SubnetId=subnet_public,
    AllocationId=eip
)["NatGateway"]["NatGatewayId"]

while True:
    state = ec2.describe_nat_gateways(NatGatewayIds=[nat])["NatGateways"][0]["State"]
    print(f"    NAT: {state}")
    if state == "available":
        break
    time.sleep(10)

print("\n=== ROUTE TABLES ===")

# Pública
rt_public = ec2.create_route_table(VpcId=vpc)["RouteTable"]["RouteTableId"]
ec2.create_route(
    RouteTableId=rt_public,
    DestinationCidrBlock="0.0.0.0/0",
    GatewayId=igw
)
ec2.associate_route_table(RouteTableId=rt_public, SubnetId=subnet_public)

# Backend (NAT)
rt_backend = ec2.create_route_table(VpcId=vpc)["RouteTable"]["RouteTableId"]
ec2.create_route(
    RouteTableId=rt_backend,
    DestinationCidrBlock="0.0.0.0/0",
    NatGatewayId=nat
)
ec2.associate_route_table(RouteTableId=rt_backend, SubnetId=subnet_backend)

# DB (aislada)
rt_db = ec2.create_route_table(VpcId=vpc)["RouteTable"]["RouteTableId"]
ec2.associate_route_table(RouteTableId=rt_db, SubnetId=subnet_db)

print("\n=== SECURITY GROUPS ===")

frontend_sg = ec2.create_security_group(
    GroupName="frontend-sg",
    Description="Frontend public access",
    VpcId=vpc
)["GroupId"]

ec2.authorize_security_group_ingress(
    GroupId=frontend_sg,
    IpPermissions=[
        {"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22,
         "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},
        {"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80,
         "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}
    ]
)

backend_sg = ec2.create_security_group(
    GroupName="backend-sg",
    Description="Backend private access",
    VpcId=vpc
)["GroupId"]

ec2.authorize_security_group_ingress(
    GroupId=backend_sg,
    IpPermissions=[
        {"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22,
         "UserIdGroupPairs": [{"GroupId": frontend_sg}]}
    ]
)

db_sg = ec2.create_security_group(
    GroupName="db-sg",
    Description="Database isolated",
    VpcId=vpc
)["GroupId"]

ec2.authorize_security_group_ingress(
    GroupId=db_sg,
    IpPermissions=[
        {"IpProtocol": "tcp", "FromPort": 3306, "ToPort": 3306,
         "UserIdGroupPairs": [{"GroupId": backend_sg}]}
    ]
)

print("\n=== INSTANCIAS ===")

frontend = ec2.run_instances(
    ImageId=AMI,
    InstanceType=INSTANCE_TYPE,
    KeyName=KEY_NAME,
    MinCount=1,
    MaxCount=1,
    NetworkInterfaces=[{
        "SubnetId": subnet_public,
        "DeviceIndex": 0,
        "AssociatePublicIpAddress": True,
        "Groups": [frontend_sg]
    }]
)["Instances"][0]["InstanceId"]

backend = ec2.run_instances(
    ImageId=AMI,
    InstanceType=INSTANCE_TYPE,
    KeyName=KEY_NAME,
    MinCount=1,
    MaxCount=1,
    NetworkInterfaces=[{
        "SubnetId": subnet_backend,
        "DeviceIndex": 0,
        "AssociatePublicIpAddress": False,
        "Groups": [backend_sg]
    }]
)["Instances"][0]["InstanceId"]

db = ec2.run_instances(
    ImageId=AMI,
    InstanceType=INSTANCE_TYPE,
    KeyName=KEY_NAME,
    MinCount=1,
    MaxCount=1,
    NetworkInterfaces=[{
        "SubnetId": subnet_db,
        "DeviceIndex": 0,
        "AssociatePublicIpAddress": False,
        "Groups": [db_sg]
    }]
)["Instances"][0]["InstanceId"]

wait_instance(frontend)
wait_instance(backend)
wait_instance(db)

print("\n✔ ESCENARIO 3 CAPAS CREADO CORRECTAMENTE")
