using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;
using TodoListService.Models;

namespace TodoListService.Controllers
{
    [Route("api/[controller]")]
    [Authorize]
    public class TodoListController : Controller
    {
        private static readonly ConcurrentBag<TodoItem> TodoStore = new ConcurrentBag<TodoItem>();
        private static readonly string[] scopeRequiredByApi = new[] {"user_impersonation", "access_as_user"};

        [HttpGet]
        public IEnumerable<TodoItem> Get()
        {
            HttpContext.VerifyUserHasAnyAcceptedScope(scopeRequiredByApi);
            var owner = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            return TodoStore.Where(t => t.Owner == owner).ToList();
        }

        [HttpPost]
        public void Post([FromBody] TodoItem todo)
        {
            HttpContext.VerifyUserHasAnyAcceptedScope(scopeRequiredByApi);
            var owner = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            TodoStore.Add(new TodoItem() {Owner = owner, Title = todo.Title});
        }
    }
}
