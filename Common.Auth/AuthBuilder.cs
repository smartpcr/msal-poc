using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.AzureAD.UI;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Common.Auth
{
    public static class AuthBuilder
    {
        public static void AddAadAuth(this IServiceCollection services)
        {
            var serviceProvider = services.BuildServiceProvider();
            var configuration = serviceProvider.GetRequiredService<IConfiguration>();
            services.AddAuthentication(AzureADDefaults.JwtBearerAuthenticationScheme)
                .AddAzureADBearer(options => configuration.Bind(nameof(AzureAd), options));
            services.AddSession();

            services.Configure<JwtBearerOptions>(AzureADDefaults.JwtBearerAuthenticationScheme,
                options =>
                {
                    // need to re-initialize since it's changed to JwtBearerOptions
                    configuration.Bind(nameof(AzureAd), options);
                    options.Authority += "/v2.0";
                    options.TokenValidationParameters.ValidAudiences = new[]{options.Audience, $"api://{options.Audience}"};
                    //options.TokenValidationParameters.IssuerValidator = AadIssuerValidator.
                });
        }
    }
}