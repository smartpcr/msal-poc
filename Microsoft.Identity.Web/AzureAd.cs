using System;

namespace Microsoft.Identity.Web
{
    public class AzureAd
    {
        public string TenantId { get; set; }
        public string ClientId { get; set; }
        public string ClientCertName { get; set; }
        public string Domain { get; set; }
        public string InstanceId { get; set; }
        public Uri Authority => new Uri($"https://login.microsoftonline.com/{TenantId}/v2.0");
    }
}