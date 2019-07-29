using System.Collections.Generic;
using System.Configuration;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using Microsoft.Identity.Client;
using Newtonsoft.Json;

namespace TodoListClient
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        private static readonly string AadInstance = ConfigurationManager.AppSettings["ida:AADInstance"];
        private static readonly string Tenant = ConfigurationManager.AppSettings["ida:Tenant"];
        private static readonly string ClientId = ConfigurationManager.AppSettings["ida:ClientId"];
        private static readonly string Authority = string.Format(CultureInfo.InvariantCulture, AadInstance, Tenant);

        private static readonly string TodoListScope = ConfigurationManager.AppSettings["todo:TodoListScope"];
        private static readonly string TodoListBaseAddress = ConfigurationManager.AppSettings["todo:TodoListBaseAddress"];
        private static readonly string[] Scopes = { TodoListScope };

        private readonly HttpClient _httpClient = new HttpClient();
        private readonly IPublicClientApplication _app;

        const string SignInString = "Sign In";
        const string ClearCacheString = "Clear Cache";

        public MainWindow()
        {
            InitializeComponent();
            _app = PublicClientApplicationBuilder.Create(ClientId)
                .WithAuthority(Authority)
                .WithDefaultRedirectUri()
                .Build();
            TokenCacheHelper.EnableSerialization(_app.UserTokenCache);

        }

        private async void SignIn(object sender, RoutedEventArgs e)
        {
            var accounts = (await _app.GetAccountsAsync()).ToList();
            if (SignInButton.Content.ToString() == ClearCacheString)
            {
                TodoList.ItemsSource = string.Empty;
                while (accounts.Any())
                {
                    await _app.RemoveAsync(accounts.First());
                    accounts = (await _app.GetAccountsAsync()).ToList();
                }

                SignInButton.Content = SignInString;
                UserName.Content = TodoListClient.Resources.UserNotSignedIn;
            }

            try
            {
                var result = await _app.AcquireTokenInteractive(Scopes)
                    .WithAccount(accounts.FirstOrDefault())
                    .WithPrompt(Prompt.SelectAccount)
                    .ExecuteAsync()
                    .ConfigureAwait(false);
                Dispatcher.Invoke(() =>
                {
                    SignInButton.Content = ClearCacheString;
                    SetUserName(result.Account);
                    GetTodoList();
                });
            }
            catch (MsalException ex)
            {
                if (ex.ErrorCode == "access_denied")
                {
                    // The user canceled sign in, take no action.
                }
                else
                {
                    string message = ex.Message;
                    if (ex.InnerException != null)
                    {
                        message += "Error Code: " + ex.ErrorCode + "Inner Exception : " + ex.InnerException.Message;
                    }

                    MessageBox.Show(message);
                }

                UserName.Content = TodoListClient.Resources.UserNotSignedIn;
            }
        }

        private void GetTodoList()
        {
            GetTodoList(SignInButton.Content.ToString() != ClearCacheString)
                .GetAwaiter().GetResult();
        }

        private async Task GetTodoList(bool isAppStarting)
        {
            var result = await TryAuthenticate();

            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", result?.AccessToken);
            var response = await _httpClient.GetAsync(TodoListBaseAddress + "/api/todolist");
            var todoArray = await ReadResponse<List<TodoItem>>(response);
            if (todoArray != null)
            {
                Dispatcher.Invoke(() => { TodoList.ItemsSource = todoArray.Select(t => new {t.Title}); });
            }
        }

        private async void AddTodoItem(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrEmpty(TodoText.Text))
            {
                MessageBox.Show("Please enter a valud for the todo item name");
                return;
            }

            var result = await TryAuthenticate();
            _httpClient.DefaultRequestHeaders.Authorization=new AuthenticationHeaderValue("Bearer", result?.AccessToken);

            TodoItem todoItem = new TodoItem() { Title = TodoText.Text };
            string json = JsonConvert.SerializeObject(todoItem);
            StringContent content = new StringContent(json, Encoding.UTF8, "application/json");
            HttpResponseMessage response = await _httpClient.PostAsync(TodoListBaseAddress + "/api/todolist", content);
            if (await ReadResponse(response))
            {
                TodoText.Text = "";
                GetTodoList();
            }
        }

        private async Task<AuthenticationResult> TryAuthenticate()
        {
            var accounts = (await _app.GetAccountsAsync()).ToList();
            if (!accounts.Any())
            {
                MessageBox.Show("Please sign in first");
                return null;
            }

            AuthenticationResult result = null;
            try
            {
                result = await _app.AcquireTokenSilent(Scopes, accounts.FirstOrDefault())
                    .ExecuteAsync().ConfigureAwait(false);
                SetUserName(result.Account);
                UserName.Content = TodoListClient.Resources.UserNotSignedIn;
            }
            catch (MsalUiRequiredException)
            {
                MessageBox.Show("Please re-sign");
                SignInButton.Content = SignInString;
            }
            catch (MsalException ex)
            {
                string message = ex.Message;
                if (ex.InnerException != null)
                {
                    message += "Error Code: " + ex.ErrorCode + "Inner Exception : " + ex.InnerException.Message;
                }

                Dispatcher.Invoke(() =>
                {
                    UserName.Content = TodoListClient.Resources.UserNotSignedIn;
                    MessageBox.Show("Unexpected error: " + message);
                });

                return null;
            }

            return result;
        }

        private void SetUserName(IAccount account)
        {
            var userName = account?.Username ?? TodoListClient.Resources.UserNotIdentified;
            UserName.Content = userName;
        }

        private async Task<T> ReadResponse<T>(HttpResponseMessage response)
        {
            if (response.IsSuccessStatusCode)
            {
                var responseString = await response.Content.ReadAsStringAsync();
                var result = JsonConvert.DeserializeObject<T>(responseString);
                return result;
            }
            else
            {
                string failureDescription = await response.Content.ReadAsStringAsync();
                MessageBox.Show($"{response.ReasonPhrase}\n {failureDescription}", "An error occurred while posting to /api/todolist", MessageBoxButton.OK);
                return default(T);
            }
        }

        private async Task<bool> ReadResponse(HttpResponseMessage response)
        {
            if (response.IsSuccessStatusCode)
            {
                return true;
            }

            string failureDescription = await response.Content.ReadAsStringAsync();
            MessageBox.Show($"{response.ReasonPhrase}\n {failureDescription}", "An error occurred while posting to /api/todolist", MessageBoxButton.OK);
            return false;
        }
    }
}
