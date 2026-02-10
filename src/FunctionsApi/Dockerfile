# Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /app

COPY ppp-globe.sln ./
COPY src/ ./src/

RUN dotnet restore src/FunctionsApi/FunctionsApi.csproj

RUN dotnet publish src/FunctionsApi/FunctionsApi.csproj -c Release -o /out --no-restore

# Runtime (Functions isolated worker for Linux)
FROM mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated8.0
WORKDIR /home/site/wwwroot
COPY --from=build /out ./

ENV ASPNETCORE_URLS=http://0.0.0.0:80
