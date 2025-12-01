<?php
// --- Conexión a BD usando las variables de entorno de EB ---
$dbhost = $_SERVER['RDS_HOSTNAME'];
$dbport = $_SERVER['RDS_PORT'];
$dbname = 'instituto';
$username = $_SERVER['RDS_USERNAME'];
$password = $_SERVER['RDS_PASSWORD'];

$charset = 'utf8';
$dsn = "mysql:host={$dbhost};port={$dbport};dbname={$dbname};charset={$charset}";

try {
    $pdo = new PDO($dsn, $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // --- Consultamos todos los alumnos ---
    $stmt = $pdo->query("SELECT id_alumno, nombre, apellido FROM alumnos ORDER BY id_alumno ASC");
    $alumnos = $stmt->fetchAll(PDO::FETCH_ASSOC);

} catch (PDOException $e) {
    die("Error de conexión: " . $e->getMessage());
}
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Listado de Alumnos</title>
    <style>
        table {
            border-collapse: collapse;
            width: 60%;
            margin: 20px auto;
        }
        th, td {
            border: 1px solid #ccc;
            padding: 8px;
            text-align: left;
        }
        th {
            background: #eee;
        }
        body {
            font-family: Arial;
        }
    </style>
</head>
<body>

<h1 style="text-align:center;">Listado de Alumnos</h1>

<table>
    <tr>
        <th>ID</th>
        <th>Nombre</th>
        <th>Apellido</th>
    </tr>

    <?php foreach ($alumnos as $alumno): ?>
        <tr>
            <td><?= $alumno['id_alumno'] ?></td>
            <td><?= htmlspecialchars($alumno['nombre']) ?></td>
            <td><?= htmlspecialchars($alumno['apellido']) ?></td>
        </tr>
    <?php endforeach; ?>
</table>

</body>
</html>
