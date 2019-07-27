using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Identity.Web;

namespace Common.Auth
{
    public static class AuthBuilder
    {
        public static bool IsAadAuthEnabled(this IConfiguration configuration)
        {
            return configuration.GetSection(nameof(AzureAd)) != null;
        }

        public static void AddAadAuth(this IServiceCollection services)
        {
            services.AddProtectWebApiWithMicrosoftIdentityPlatformV2();
        }
    }
}