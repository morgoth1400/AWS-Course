<?php
include("db.php");

$result = $conn->query("SELECT id, nombre, email FROM clientes");
?>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Listado de Clientes</title>
</head>
<body>

<h1>Clientes</h1>

<table border="1" cellpadding="6">
    <tr>
        <th>ID</th>
        <th>Nombre</th>
        <th>Email</th>
    </tr>

    <?php while ($row = $result->fetch_assoc()) : ?>
        <tr>
            <td><?= $row['id'] ?></td>
            <td><?= $row['nombre'] ?></td>
            <td><?= $row['email'] ?></td>
        </tr>
    <?php endwhile; ?>

</table>

</body>
</html>
