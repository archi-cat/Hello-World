from diagrams import Diagram, Cluster, Edge
from diagrams.azure.network import ApplicationGateway, VirtualNetworks, Subnets, PublicIpAddresses
from diagrams.azure.compute import AppServices, ContainerRegistries
from diagrams.azure.database import SQLDatabases, SQLServers
from diagrams.azure.monitor import ApplicationInsights, LogAnalyticsWorkspaces, Monitor
from diagrams.azure.identity import ManagedIdentities, Groups
from diagrams.azure.storage import StorageAccounts
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github

graph_attr = {
    "fontsize": "14",
    "fontname": "Helvetica",
    "bgcolor": "white",
    "pad": "0.75",
    "splines": "ortho",
    "nodesep": "0.6",
    "ranksep": "0.9",
}

node_attr = {
    "fontsize": "11",
    "fontname": "Helvetica",
}

with Diagram(
    "Hello World — Azure Two-Tier Application",
    filename="/home/claude/azure_architecture",
    outformat="png",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    node_attr=node_attr,
):
    user    = Users("User\n(internet)")
    github  = Github("GitHub\n(source + pipelines)")

    with Cluster("GitHub Actions CI/CD"):
        acr = ContainerRegistries("Azure Container\nRegistry (ACR)")

    pub_ip = PublicIpAddresses("Public IP")

    with Cluster("Azure Subscription — rg-hello-world"):

        with Cluster("Networking"):
            gateway = ApplicationGateway("App Gateway\nStandard V2")
            vnet    = VirtualNetworks("VNet\n10.0.0.0/16")

        with Cluster("VNet — App Services"):
            with Cluster("web-subnet  10.0.1.0/24"):
                web_app = AppServices("Web App\nFlask · port 8000")

            with Cluster("api-subnet  10.0.2.0/24"):
                api_app = AppServices("API\nFlask · port 8000")

        with Cluster("Data"):
            sql_server = SQLServers("SQL Server\nsql-hello-world")
            sql_db     = SQLDatabases("SQL Database\nBasic · 5 DTUs")

        with Cluster("Identity"):
            api_mi = ManagedIdentities("API Managed\nIdentity")
            sql_admin_group = Groups("Entra Group\nsql-admins")

        with Cluster("Observability"):
            appi_web = ApplicationInsights("App Insights\n(web)")
            appi_api = ApplicationInsights("App Insights\n(api)")
            log_ws   = LogAnalyticsWorkspaces("Log Analytics\nWorkspace")
            dtu_alert = Monitor("DTU Alert\n85% · 20 min")

        with Cluster("Terraform Remote State\nrg-terraform-state"):
            tf_state = StorageAccounts("Blob Storage\ntfstate")

    # ── Traffic flow ──────────────────────────────────────────────────────────
    user     >> Edge(label="HTTP :80")         >> pub_ip
    pub_ip   >> Edge(color="black")            >> gateway
    gateway  >> Edge(label="HTTPS :443")       >> web_app
    web_app  >> Edge(label="HTTPS /db-check")  >> api_app

    # ── Managed Identity → SQL ────────────────────────────────────────────────
    api_app  >> Edge(label="token auth",
                     color="darkgreen",
                     style="dashed")           >> api_mi
    api_mi   >> Edge(label="Entra token",
                     color="darkgreen",
                     style="dashed")           >> sql_server
    sql_server >> Edge(color="gray")           >> sql_db

    # ── Observability ─────────────────────────────────────────────────────────
    web_app  >> Edge(color="orange",
                     style="dashed")           >> appi_web
    api_app  >> Edge(color="orange",
                     style="dashed")           >> appi_api
    appi_web >> Edge(color="orange",
                     style="dashed")           >> log_ws
    appi_api >> Edge(color="orange",
                     style="dashed")           >> log_ws
    sql_db   >> Edge(color="red",
                     style="dashed",
                     label="DTU metric")       >> dtu_alert

    # ── CI/CD ─────────────────────────────────────────────────────────────────
    github   >> Edge(label="docker push",
                     color="steelblue",
                     style="dashed")           >> acr
    acr      >> Edge(label="pull on deploy",
                     color="steelblue",
                     style="dashed")           >> web_app
    acr      >> Edge(color="steelblue",
                     style="dashed")           >> api_app
    github   >> Edge(label="terraform apply",
                     color="purple",
                     style="dashed")           >> tf_state

    # ── Entra admin on SQL server ─────────────────────────────────────────────
    sql_admin_group >> Edge(label="Entra admin",
                            color="darkgreen",
                            style="dotted")    >> sql_server

print("Diagram generated successfully.")
