/**
 * TodoMVC - Vanilla JavaScript for editing and keyboard shortcuts
 * Handles double-click to edit and Enter/Escape key bindings
 */

// Edit a todo (called on double-click)
function editTodo(todoId) {
  const todoItem = document.getElementById(`todo-${todoId}`);
  const editInput = document.getElementById(`edit-${todoId}`);

  if (!todoItem || !editInput) return;

  // Add editing class to show input
  todoItem.classList.add('editing');

  // Focus and select all text in input
  editInput.focus();
  editInput.select();

  // Store original value in case user cancels
  editInput.dataset.originalValue = editInput.value;
}

// Cancel editing (called on blur or Escape)
function cancelEdit(todoId) {
  const todoItem = document.getElementById(`todo-${todoId}`);
  const editInput = document.getElementById(`edit-${todoId}`);

  if (!todoItem || !editInput) return;

  // Remove editing class to hide input
  todoItem.classList.remove('editing');

  // Restore original value
  if (editInput.dataset.originalValue) {
    editInput.value = editInput.dataset.originalValue;
  }
}

// Save todo edit (called on Enter)
function saveTodoEdit(todoId) {
  const todoItem = document.getElementById(`todo-${todoId}`);
  const editInput = document.getElementById(`edit-${todoId}`);

  if (!todoItem || !editInput) return;

  const newTitle = editInput.value.trim();

  // If empty, delete the todo
  if (newTitle === '') {
    if (confirm('Delete this todo?')) {
      // Trigger HTMX delete
      const deleteBtn = todoItem.querySelector('.destroy');
      if (deleteBtn) {
        deleteBtn.click();
      }
    } else {
      cancelEdit(todoId);
    }
    return;
  }

  // If unchanged, just cancel
  if (newTitle === editInput.dataset.originalValue) {
    cancelEdit(todoId);
    return;
  }

  // Send PATCH request to update todo
  fetch(`/todos/${todoId}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ title: newTitle }),
  })
    .then(response => {
      if (!response.ok) throw new Error('Failed to update todo');
      return response.text();
    })
    .then(html => {
      // Replace the todo item with updated HTML
      todoItem.outerHTML = html;
    })
    .catch(error => {
      console.error('Error updating todo:', error);
      cancelEdit(todoId);
    });
}

// Handle keyboard events during editing
function handleEditKeydown(event, todoId) {
  if (event.key === 'Enter') {
    event.preventDefault();
    saveTodoEdit(todoId);
  } else if (event.key === 'Escape') {
    event.preventDefault();
    cancelEdit(todoId);
  }
}

// Initialize event listeners
document.addEventListener('DOMContentLoaded', () => {
  console.log('TodoMVC initialized');

  // Add global keyboard shortcut info
  console.log('Keyboard shortcuts:');
  console.log('  • Double-click todo to edit');
  console.log('  • Enter to save');
  console.log('  • Escape to cancel');
});

// Handle HTMX events
document.addEventListener('htmx:afterSwap', (event) => {
  // If we swapped in new todos, ensure editing still works
  console.log('Content swapped');
});

document.addEventListener('htmx:responseError', (event) => {
  console.error('HTMX request failed:', event.detail);
  alert('An error occurred. Please try again.');
});
