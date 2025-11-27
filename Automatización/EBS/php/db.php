<?php
$host = $_SERVER['RDS_HOSTNAME'];
$user = $_SERVER['RDS_USERNAME'];
$pass = $_SERVER['RDS_PASSWORD'];
$dbname = $_SERVER['RDS_DB_NAME'];
$port = $_SERVER['RDS_PORT'];

$conn = new mysqli($host, $user, $pass, $dbname, $port);

if ($conn->connect_errno) {
    echo "Error de conexión: " . $conn->connect_error;
    exit();
}
?>
