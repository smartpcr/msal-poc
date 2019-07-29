using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using Microsoft.Identity.Client;

namespace TodoListClient
{
    public static class TokenCacheHelper
    {
        private static readonly string CacheFilePath =
            Assembly.GetExecutingAssembly().Location +
            "msalcache.bin";
        private static readonly object FileLock = new object();

        internal static void EnableSerialization(ITokenCache tokenCache)
        {
            tokenCache.SetBeforeAccess(BeforeAccessNotification);
            tokenCache.SetAfterAccess(AfterAccessNotification);
        }

        private static void BeforeAccessNotification(TokenCacheNotificationArgs args)
        {
            lock (FileLock)
            {
                var cacheContent = File.Exists(CacheFilePath)
                    ? ProtectedData.Unprotect(File.ReadAllBytes(CacheFilePath), null, DataProtectionScope.CurrentUser)
                    : null;
                args.TokenCache.DeserializeAdalV3(cacheContent);
            }
        }

        private static void AfterAccessNotification(TokenCacheNotificationArgs args)
        {
            if (args.HasStateChanged)
            {
                lock (FileLock)
                {
                    File.WriteAllBytes(CacheFilePath, ProtectedData.Protect(
                        args.TokenCache.SerializeMsalV3(), null, DataProtectionScope.CurrentUser));
                }
            }
        }
    }
}