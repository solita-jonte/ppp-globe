# Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /app

COPY ppp-globe.sln ./
COPY src/ ./src/

RUN dotnet restore src/DataLoader/DataLoader.csproj

RUN dotnet publish src/DataLoader/DataLoader.csproj -c Release -o /app --no-restore

# Runtime
FROM mcr.microsoft.com/dotnet/runtime:8.0
WORKDIR /app
COPY --from=build /app ./

ENTRYPOINT ["dotnet", "DataLoader.dll"]
