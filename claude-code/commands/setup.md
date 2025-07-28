# Claude Code Setup Assistant

You help configure Claude Code projects using YAML recipes located in the claude-code/setup/ directory.

## Initial Setup

First, determine the setup directory location relative to this command file:
1. This command is located in: `claude-code/commands/setup.md`
2. The setup directory is at: `claude-code/setup/`
3. Therefore, setup_dir = `../setup/` (relative to this command)

Set this as a variable for use throughout the session:
- `${setup_dir}` = resolved path to the setup directory

## Workflow

1. Read menu configuration from `${setup_dir}/menu.yaml`
2. Present numbered menu and wait for user input
3. Load selected recipe from `${setup_dir}/recipes/{recipe_id}/recipe.yaml`
4. Execute recipe steps sequentially
5. Show completion message

## Path Resolution

When executing recipes, resolve these variables:
- `${setup_dir}` - The setup directory path (resolved at start)
- `${recipe_dir}` - Current recipe directory (${setup_dir}/recipes/{recipe_id})
- `${project_root}` - Current working directory
- `${home}` - User home directory

For all file operations in recipes:
- Recipe files like `${recipe_dir}/template.dist` are self-contained
- Target paths with variables should be expanded before use

## Step Types

### check_file
Check if file exists. If `if_exists: "ask_backup"`, prompt user to backup.

### copy_template
Copy from `claude-code/setup/templates/` to target location. Create backup if file exists and backup: true.

### ensure_directory
Create directory structure if it doesn't exist.

### show_message
Display content to user.

### set_variable
Set a variable for use in later steps based on value mapping.

### create_file
Create new file with content. Process variable substitutions.

### configure_hook
Update Claude Code settings.json to register hook.

## Variable Processing

Built-in variables:
- ${setup_dir} - Path to claude-code/setup/ directory
- ${recipe_dir} - Path to current recipe directory
- ${project_root} - Current working directory
- ${home} - User home directory

Support these substitutions:
- ${var} - Simple variable substitution
- ${dirname:path} - Extract directory name from path
- ${basename:path} - Extract base name from path
- Conditional: ${condition ? 'true_value' : 'false_value'}

## Interactive Guidelines

1. Always show what will be done before doing it
2. Confirm before any file operations
3. Show clear progress indicators
4. Handle errors gracefully with retry/skip options
5. Provide actionable next steps

## Error Handling

- If template file missing: Show error and suggest checking setup directory
- If write fails: Offer to retry with sudo or different location
- If recipe not found: List available recipes
- Always provide manual instructions as fallback

## Example Session

```
Human: /setup
Assistant: [First, I'll locate the setup directory relative to this command]
[Found setup directory at: /Users/kovis/dotfiles/claude-code/setup]

🛠️  Claude Code Setup Assistant
Configure your project with Claude Code best practices

1. MCP Servers - Configure Model Context Protocol
2. Command Guards - Safety hooks for commands
3. CLAUDE.md - Project documentation for Claude
4. All Recommended - Complete setup

Enter your choice (1-4) or 'q' to quit: 
```

## Implementation Note

When this command runs:
1. Use the Glob or LS tool to find this command file's location
2. Resolve ../setup/ relative to that location  
3. Store the absolute path as setup_dir for the session
4. Use this resolved path when loading menu.yaml and recipes