```mermaid
graph TD
    %% Definições de estilo
    classDef azure fill:#0072C6,stroke:#fff,stroke-width:2px,color:#fff;
    classDef vnet fill:#e6f2ff,stroke:#0072C6,stroke-width:2px,stroke-dasharray: 5 5;
    classDef subnet fill:#ffffff,stroke:#0072C6,stroke-width:1px;
    classDef nsg fill:#f8f9fa,stroke:#dc3545,stroke-width:2px;
    classDef vm fill:#d4edda,stroke:#28a745,stroke-width:2px;
    classDef db fill:#fff3cd,stroke:#ffc107,stroke-width:2px;
    classDef disk fill:#e2e3e5,stroke:#6c757d,stroke-width:2px;

    %% Atores Externos
    subgraph Externa [Rede Externa]
        Client([Internet / Clientes])
        LabAdmin([IP Público do Lab])
    end

    %% Nuvem Azure
    subgraph Azure [Microsoft Azure - Central US]
        subgraph RG [Resource Group: rg-marcozero-hom-gl]
            
            subgraph VNet [Virtual Network: vnet-marcozero 10.0.0.0/16]
                direction TB
                
                %% Sub-rede de Aplicação
                subgraph AppSubnet [app-subnet: 10.0.1.0/24]
                    direction TB
                    NSG_Pub[NSG-Public<br/>Libera: 80, 443<br/>Libera: 22 restrito ao Lab]:::nsg
                    VM_App[VM-APP<br/>Ubuntu 22.04 + Nginx + PM2<br/>IP Público Estático]:::vm
                    NSG_Pub --- VM_App
                end

                %% Sub-rede de Dados
                subgraph DataSubnet [data-subnet: 10.0.2.0/24]
                    direction TB
                    NSG_Priv[NSG-Private<br/>Libera: 3306 da app-subnet<br/>Libera: 22 da app-subnet]:::nsg
                    VM_Db[(VM-DB<br/>Ubuntu + MySQL 8<br/>Sem IP Público)]:::db
                    Disk[(Disco Premium SSD 32GB<br/>/mnt/mysql-data)]:::disk
                    
                    NSG_Priv --- VM_Db
                    VM_Db --- Disk
                end
            end
        end
    end

    %% Conexões e Tráfego
    Client -- "HTTP (80) / HTTPS (443)" --> NSG_Pub
    LabAdmin -- "SSH (22)" --> NSG_Pub
    
    VM_App -- "Tráfego MySQL (3306)" --> NSG_Priv
    VM_App -. "Acesso SSH via Bastion Host (22)" .-> NSG_Priv

    %% Aplicação de estilos
    class Azure azure;
    class VNet vnet;
    class AppSubnet,DataSubnet subnet;