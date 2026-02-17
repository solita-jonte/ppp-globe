using Microsoft.Azure.Functions.Worker.Http;

namespace FunctionsApi;

public static class CorsHelper
{
    public static void AllowAny(HttpResponseData response)
    {
        response.Headers.Add("Access-Control-Allow-Origin", "*");
        response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, Authorization");
    }
}
