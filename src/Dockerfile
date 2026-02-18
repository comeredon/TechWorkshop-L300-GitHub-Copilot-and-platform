# syntax=docker/dockerfile:1

# ── Build stage ───────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Restore dependencies first (layer-cached)
COPY ["ZavaStorefront.csproj", "."]
RUN dotnet restore "ZavaStorefront.csproj"

# Copy source and publish
COPY . .
RUN dotnet publish "ZavaStorefront.csproj" -c Release -o /app/publish /p:UseAppHost=false

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

# App Service sets WEBSITES_PORT; ASP.NET Core must listen on it
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "ZavaStorefront.dll"]
