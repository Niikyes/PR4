# 🚀 PR4 - Despliegue Automático en AWS con Terraform, Docker y GitHub Actions

Este proyecto despliega automáticamente una aplicación **frontend + backend** conectada a una base de datos **PostgreSQL en AWS RDS**, utilizando:
- **Terraform**: Para crear la infraestructura (VPC, EC2, RDS).
- **Docker y DockerHub**: Para construir y publicar imágenes de backend y frontend.
- **GitHub Actions (CI/CD)**: Para automatizar el build y despliegue en AWS EC2.
- **Inyección dinámica de variables**: Configuración automática de la API en el frontend y conexión del backend con RDS.

---

## 🏗️ **Arquitectura del Proyecto**
![Arquitectura](https://www.plantuml.com/plantuml/png/ZP5DIy8m48NtEOKvMRnVnLRk2WQ2K9wL6AsfK7w7A7dHqpGjJ-M2WTvUpkgxHJvUHXAF2qK3UtRP5hUJYrR3PCEixKqFOnu3k3Pz6CYy-38a6v3y6qDML0F0IfdYQ3h5Gy4t7utP8RRXzCmP_L-pFsnGJjX2yJm6vBk1i1bIDVYpXvQk5fW00)

**Componentes:**
- **AWS VPC:** Red privada para aislar los recursos.
- **EC2 Ubuntu 22.04 (t3.micro):** Servidor donde corren los contenedores.
- **RDS PostgreSQL:** Base de datos gestionada y segura en subred privada.
- **Docker Compose:** Orquesta el backend y frontend en EC2.
- **GitHub Actions:** Pipeline CI/CD para infraestructura y despliegue.

---

## 📂 **Estructura del Proyecto**
PR4/
├── backend/ # Código backend (Node.js)
│ ├── .env # Variables locales (solo dev)
│ ├── Dockerfile
│ ├── db.js
│ └── index.js
│
├── frontend/ # Código frontend (HTML/JS)
│ ├── Dockerfile
│ ├── index.html
│ └── joke.html
│
├── infra/ # Infraestructura con Terraform
│ ├── main.tf # Recursos AWS (VPC, EC2, RDS, SG)
│ ├── variables.tf # Variables reutilizables
│ └── outputs.tf # Outputs (IP EC2, endpoint RDS)
│
├── .github/workflows/
│ ├── deploy-infra.yml # Despliegue Infraestructura (Terraform)
│ └── deploy-app.yml # CI/CD: Build Docker + Deploy EC2
│
├── docker-compose.yml # Orquestación de servicios
└── README.md


---

## ⚙️ **Flujo de Despliegue**

### 1️⃣ **Infraestructura con Terraform**
- Se crea una **VPC** privada con subnets públicas y privadas.
- Se lanza una **instancia EC2 Ubuntu 22.04 (t3.micro)** con Docker y Docker Compose instalados automáticamente.
- Se despliega una **RDS PostgreSQL** (nombre BD: `test`, usuario: `postgres`, contraseña: `12345678`).
- **Security Groups configurados:**
  - EC2: SSH (22), HTTP (80) y API Backend (8080) abiertos.
  - RDS: Solo acepta conexiones internas desde el SG de la EC2.

---

### 2️⃣ **Pipeline CI/CD con GitHub Actions**

Se usan **dos workflows independientes**:

#### 🔹 `deploy-infra.yml` (Infraestructura AWS con Terraform)
- Configura AWS CLI usando credenciales de **AWS Educate**.
- Ejecuta `terraform init`, `plan` y `apply`.
- Genera outputs (`ec2_public_ip`, `rds_endpoint`).
- Crea una clave SSH `pr4-key.pem` automáticamente para conectar EC2.

#### 🔹 `deploy-app.yml` (CI/CD de la aplicación)
- Construye imágenes **Docker** de `backend` y `frontend`.
- Publica en **DockerHub**.
- Obtiene la **IP EC2** y **endpoint de RDS** de Terraform.
- Reemplaza dinámicamente en el frontend (`index.html` y `joke.html`) la IP de la API:
  ```javascript
  const API_URL = "http://<EC2_PUBLIC_IP>:8080";
