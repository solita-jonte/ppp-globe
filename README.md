# PPP Globe

PPP Globe is a small multi-component project for exploring how purchasing power parity (PPP)–adjusted GDP per capita has developed across countries over time, and ultimately visualizing it on an interactive 3D globe. The stack consists of a SQL Server database, a C# data loader that pulls data from the World Bank API into that database, and (later) a C# backend API plus a JavaScript frontend that will serve and visualize the data.

## Components

- **Database (SQL Server in Docker)**  
  Stores:
  - `Country` (ISO codes, names)
  - `PppGdpPerCapita` (GDP per capita, PPP, per country-year)

- **DataLoader (C# console app)**  
  - Database initializer, runs at startup
  - Downloads country metadata from the World Bank `/country` endpoint.
  - Filters out data, only keeps real countries.
  - Downloads PPP-adjusted GDP per capita (`NY.GDP.PCAP.PP.KD`), keeps data for countries (not regions).
  - Inserts/updates records in the SQL Server database via EF Core.

- **Backend server**  
  - ASP.NET Core backend API to serve the aggregated PPP data in JSON format.

- **Frontend view**
  - JavaScript frontend to render a globe with a time slider based on the DB data.

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
└─ src/
   ├─ DataLoader/
   │  ├─ DataLoader.csproj
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

## How to Run

1.  **Start everything with Docker:**

    ```bash
    docker-compose up --build
    ```

2.  **What happens:**
    
    -   `db`: SQL Server starts and listens on `localhost:${DB_PORT}`.
    -   `db-init`: runs `db/init/01-init.sql` to create `PppDb`, `Country`, and `PppGdpPerCapita`.
    -   `dataloader`: runs the C# data loader console app, which:
        -   Fetches the list of real countries from the World Bank API.
        -   Populates the `Country` table.
        -   Downloads PPP GDP per capita (`NY.GDP.PCAP.PP.KD`) and stores it in `PppGdpPerCapita`.

3.  **Inspect the database (optional):**

    -   Server: `localhost,${DB_PORT}` (e.g. `localhost,1433`)
    -   User: `sa`
    -   Password: `SA_PASSWORD` from `.env`
    -   Database: `PppDb`
