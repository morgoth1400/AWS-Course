const mensaje = document.getElementById("mensaje");

mensaje.addEventListener("mouseover", () => {
    mensaje.style.transform = "rotate(360deg)";
});

mensaje.addEventListener("mouseout", () => {
    mensaje.style.transform = "rotate(0deg)";
});
