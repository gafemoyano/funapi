/**
 * TodoMVC - Vanilla JavaScript Client
 * Pure client-side app that talks to FunApi JSON API
 */

// API Client
const API = {
  baseURL: '/api',

  async request(method, url, body = null) {
    const options = {
      method,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    if (body) {
      options.body = JSON.stringify(body);
    }

    try {
      const response = await fetch(`${this.baseURL}${url}`, options);

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.detail || 'Request failed');
      }

      // Handle empty responses (like DELETE)
      const text = await response.text();
      return text ? JSON.parse(text) : null;
    } catch (error) {
      console.error('API Error:', error);
      throw error;
    }
  },

  async getTodos(filter = 'all') {
    const params = filter !== 'all' ? `?filter=${filter}` : '';
    return this.request('GET', `/todos${params}`);
  },

  async createTodo(title) {
    return this.request('POST', '/todos', { title });
  },

  async updateTodo(id, attrs) {
    return this.request('PATCH', `/todos/${id}`, attrs);
  },

  async deleteTodo(id) {
    return this.request('DELETE', `/todos/${id}`);
  },

  async clearCompleted() {
    return this.request('DELETE', '/todos/completed/all');
  },

  async toggleAll(completed) {
    return this.request('POST', '/todos/toggle-all', { completed });
  }
};

// App State
const state = {
  todos: [],
  filter: 'all',
  stats: { active_count: 0, completed_count: 0, total_count: 0 },
  editingId: null
};

// DOM Elements
const elements = {
  newTodoForm: document.getElementById('new-todo-form'),
  newTodoInput: document.getElementById('new-todo-input'),
  todoList: document.getElementById('todo-list'),
  toggleAll: document.getElementById('toggle-all'),
  mainSection: document.getElementById('main-section'),
  footerSection: document.getElementById('footer-section'),
  activeCount: document.getElementById('active-count'),
  activeLabel: document.getElementById('active-label'),
  clearCompleted: document.getElementById('clear-completed'),
  filters: document.querySelectorAll('.filters a')
};

// Render Functions
function renderTodos() {
  const filteredTodos = filterTodos(state.todos, state.filter);

  elements.todoList.innerHTML = filteredTodos
    .map(todo => renderTodoItem(todo))
    .join('');

  // Show/hide main and footer sections
  const hasТodos = state.todos.length > 0;
  elements.mainSection.style.display = hasТodos ? 'block' : 'none';
  elements.footerSection.style.display = hasТodos ? 'block' : 'none';

  // Update toggle-all checkbox
  elements.toggleAll.checked = state.stats.active_count === 0 && state.todos.length > 0;

  // Update stats
  elements.activeCount.textContent = state.stats.active_count;
  elements.activeLabel.textContent = state.stats.active_count === 1 ? 'item' : 'items';

  // Show/hide clear completed button
  elements.clearCompleted.style.display = state.stats.completed_count > 0 ? 'block' : 'none';

  // Update filter links
  elements.filters.forEach(link => {
    const filter = link.getAttribute('data-filter');
    link.classList.toggle('selected', filter === state.filter);
  });
}

function renderTodoItem(todo) {
  const isEditing = state.editingId === todo.id;

  return `
    <li id="todo-${todo.id}"
        class="${todo.completed ? 'completed' : ''}${isEditing ? ' editing' : ''}"
        data-id="${todo.id}">
      <div class="view">
        <input
          class="toggle"
          type="checkbox"
          ${todo.completed ? 'checked' : ''}
          onchange="handleToggle(${todo.id})">
        <label ondblclick="startEdit(${todo.id})">${escapeHtml(todo.title)}</label>
        <button class="destroy" onclick="handleDelete(${todo.id})"></button>
      </div>
      <input
        class="edit"
        value="${escapeHtml(todo.title)}"
        onblur="cancelEdit(${todo.id})"
        onkeydown="handleEditKeydown(event, ${todo.id})">
    </li>
  `;
}

function filterTodos(todos, filter) {
  switch (filter) {
    case 'active':
      return todos.filter(t => !t.completed);
    case 'completed':
      return todos.filter(t => t.completed);
    default:
      return todos;
  }
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Event Handlers
async function loadTodos() {
  try {
    const data = await API.getTodos(state.filter);
    state.todos = data.todos;
    state.stats = data.stats;
    renderTodos();
  } catch (error) {
    console.error('Failed to load todos:', error);
    alert('Failed to load todos. Please try again.');
  }
}

async function handleNewTodo(event) {
  event.preventDefault();

  const title = elements.newTodoInput.value.trim();

  if (!title) return;

  try {
    const newTodo = await API.createTodo(title);
    state.todos.push(newTodo);
    state.stats.active_count++;
    state.stats.total_count++;

    elements.newTodoInput.value = '';
    renderTodos();
  } catch (error) {
    console.error('Failed to create todo:', error);
    alert('Failed to create todo. Please try again.');
  }
}

async function handleToggle(id) {
  const todo = state.todos.find(t => t.id === id);
  if (!todo) return;

  const newCompleted = !todo.completed;

  try {
    const updated = await API.updateTodo(id, { completed: newCompleted });
    Object.assign(todo, updated);

    if (newCompleted) {
      state.stats.active_count--;
      state.stats.completed_count++;
    } else {
      state.stats.active_count++;
      state.stats.completed_count--;
    }

    renderTodos();
  } catch (error) {
    console.error('Failed to toggle todo:', error);
    alert('Failed to update todo. Please try again.');
  }
}

async function handleDelete(id) {
  const todo = state.todos.find(t => t.id === id);
  if (!todo) return;

  try {
    await API.deleteTodo(id);
    state.todos = state.todos.filter(t => t.id !== id);

    if (todo.completed) {
      state.stats.completed_count--;
    } else {
      state.stats.active_count--;
    }
    state.stats.total_count--;

    renderTodos();
  } catch (error) {
    console.error('Failed to delete todo:', error);
    alert('Failed to delete todo. Please try again.');
  }
}

function startEdit(id) {
  state.editingId = id;
  renderTodos();

  // Focus and select the edit input
  const editInput = document.querySelector(`#todo-${id} .edit`);
  if (editInput) {
    editInput.focus();
    editInput.select();
  }
}

async function saveEdit(id) {
  const editInput = document.querySelector(`#todo-${id} .edit`);
  if (!editInput) return;

  const newTitle = editInput.value.trim();
  const todo = state.todos.find(t => t.id === id);

  if (!todo) return;

  // If empty, delete the todo
  if (!newTitle) {
    if (confirm('Delete this todo?')) {
      await handleDelete(id);
    } else {
      cancelEdit(id);
    }
    return;
  }

  // If unchanged, just cancel
  if (newTitle === todo.title) {
    cancelEdit(id);
    return;
  }

  try {
    const updated = await API.updateTodo(id, { title: newTitle });
    Object.assign(todo, updated);
    state.editingId = null;
    renderTodos();
  } catch (error) {
    console.error('Failed to update todo:', error);
    alert('Failed to update todo. Please try again.');
    cancelEdit(id);
  }
}

function cancelEdit(id) {
  state.editingId = null;
  renderTodos();
}

function handleEditKeydown(event, id) {
  if (event.key === 'Enter') {
    event.preventDefault();
    saveEdit(id);
  } else if (event.key === 'Escape') {
    event.preventDefault();
    cancelEdit(id);
  }
}

async function handleToggleAll() {
  const completed = elements.toggleAll.checked;

  try {
    const data = await API.toggleAll(completed);
    state.todos = data.todos;

    // Recalculate stats
    state.stats.active_count = state.todos.filter(t => !t.completed).length;
    state.stats.completed_count = state.todos.filter(t => t.completed).length;

    renderTodos();
  } catch (error) {
    console.error('Failed to toggle all:', error);
    alert('Failed to toggle all todos. Please try again.');
  }
}

async function handleClearCompleted() {
  if (!confirm('Clear all completed todos?')) return;

  try {
    await API.clearCompleted();
    state.todos = state.todos.filter(t => !t.completed);
    state.stats.completed_count = 0;
    state.stats.total_count = state.todos.length;

    renderTodos();
  } catch (error) {
    console.error('Failed to clear completed:', error);
    alert('Failed to clear completed todos. Please try again.');
  }
}

function handleFilterChange() {
  const hash = window.location.hash.replace('#/', '') || 'all';
  state.filter = hash;
  renderTodos();
}

// Event Listeners
elements.newTodoForm.addEventListener('submit', handleNewTodo);
elements.toggleAll.addEventListener('change', handleToggleAll);
elements.clearCompleted.addEventListener('click', handleClearCompleted);
window.addEventListener('hashchange', handleFilterChange);

// Initialize app
document.addEventListener('DOMContentLoaded', () => {
  console.log('TodoMVC initialized');
  console.log('Keyboard shortcuts:');
  console.log('  • Double-click todo to edit');
  console.log('  • Enter to save');
  console.log('  • Escape to cancel');

  handleFilterChange();
  loadTodos();
});
