# Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy solution and project files first (for better caching)
COPY ppp-globe.sln ./
COPY src/Domain/Domain.csproj src/Domain/
COPY src/DataLoader/DataLoader.csproj src/DataLoader/

RUN dotnet restore ./ppp-globe.sln

# Copy the rest of the source
COPY . ./

RUN dotnet publish ./src/DataLoader/DataLoader.csproj -c Release -o /app

# Runtime
FROM mcr.microsoft.com/dotnet/runtime:8.0
WORKDIR /app
COPY --from=build /app ./

ENTRYPOINT ["dotnet", "DataLoader.dll"]
