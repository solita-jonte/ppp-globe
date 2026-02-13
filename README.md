# PPP Globe

PPP Globe is a small multi-component project for exploring how purchasing power parity (PPP)–adjusted GDP per capita
has developed across countries over time, and ultimately visualizing it on an interactive 3D globe. The stack consists
of a SQL Server database, a C# data loader that pulls data from the World Bank API into that database, and a C#
serverless backend API plus a JavaScript frontend that will serve and visualize the data.

## Components

- **Database (SQL Server in Docker)**  
  Stores:
  - `Country` (ISO codes, names)
  - `PppGdpPerCapita` (GDP per capita, PPP, per country-year)

- **DataLoader, C# console app that initializes data**  
  - Database initializer, runs at startup
  - Downloads country metadata from the World Bank `/country` endpoint.
  - Filters out data, only keeps real countries.
  - Downloads PPP-adjusted GDP per capita (`NY.GDP.PCAP.PP.KD`), keeps data for countries (not regions).
  - Inserts/updates records in the SQL Server database via EF Core.

- **Serverless C# hosting app**  
  - Azure Functions API to serve the aggregated PPP data in JSON format.

- **Frontend view**
  - JavaScript frontend to render a globe with a time slider based on the DB data.

- **Deploy scripts**
  - Utilizing Azure DevOps piplines for building Docker containers, then in turn uses Terraform for creating infra and
  deploying.

## Project Structure

```text
ppp-globe/
├─ README.md
├─ .env
├─ docker-compose.yml
├─ db/
│  ├─ data/
│  └─ init/
│     └─ 01-init.sql
├─ azure/
│  ├─ deploy.sh
│  └─ teardown.sh
└─ src/
   ├─ DataLoader/
   │  ├─ DataLoader.csproj
   │  └─ Program.cs
   ├─ FunctionsApi/
   │  ├─ FunctionsApi.csproj
   │  └─ Program.cs
   ├─ Domain/
   │  └─ ...
   :
```

## Configuration

Create a `.env` file in the project root:

```env
SA_PASSWORD=Your_Str0ng_Passw0rd
DB_NAME=PppDb
DB_PORT=1433
```

## How to Run on Your Dev Machine

1.  **Start everything with Docker:**

    ```bash
    docker-compose up --build
    ```

2.  **What happens:**
    
    -   `db`: SQL Server starts and listens on `localhost:${DB_PORT}`.
    -   `db-init`: runs `db/init/01-init.sql` to create `PppDb` DB, `Country`, and `PppGdpPerCapita` tables.
    -   `dataloader`: runs the C# data loader console app, which:
        -   Fetches the list of real countries from the World Bank API.
        -   Populates the `Country` table.
        -   Downloads PPP GDP per capita (`NY.GDP.PCAP.PP.KD`) and stores it in `PppGdpPerCapita`.
    -   `functions-api`: starts the serverless hosting of the data

3.  **Inspect the data:**

    ```bash
    curl "http://127.0.0.1:7071/api/country-ppp?startYear=2018"
    ```

## How to Run on Azure

1.  **Login:**

    ```bash
    az login
    ```

2.  **Init and deploy:**

    This takes a while:

    ```bash
    ./azure/deploy.sh
    ```

3.  **View the globe:**

    Open the browser and point it towards the URL output from `deploy.sh`.

4.  **Teardown infra:**

    ```bash
    ./azure/teardown.sh
    ```

    Note that it may take a long time to finalize. I just saw the Container App Environment take 15 minutes to delete...
