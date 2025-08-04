# Claude Code Setup Assistant

You help configure Claude Code projects using YAML recipes located in the claude-code/setup/ directory.

## Initial Setup

When this command runs, locate the setup directory using this strategy:

1. Check for local project setup directory at `.claude/setup/`
   - Allows project-specific setup recipes
   - Highest priority for project customization
   
2. Check if `CLAUDE_CONFIG_DIR` environment variable is set
   - If yes: setup directory is at `$CLAUDE_CONFIG_DIR/setup/`
   - This handles custom config locations
   
3. Fallback to default user location at `~/.claude/setup/`
   - Standard Claude Code user directory

The first directory found in this order will be used as `${setup_dir}`.

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

## Variable Types

### Standard Variables
```yaml
variables:
  simple_var:
    prompt: "Enter value:"
    default: "default_value"
    
  choice_var:
    prompt: "Select option:"
    type: "choice"
    choices:
      - label: "Option 1"
        value: "opt1"
        
  multi_choice_var:
    prompt: "Select multiple:"
    type: "multi_choice"
    choices:
      - id: "id1"
        label: "Option 1"
        default: true
```

**Important**: When presenting choices to users, always display them with numbers for easy selection.

### Dynamic Choices from Files
```yaml
variables:
  dynamic_var:
    prompt: "Select option:"
    type: "choice"
    choices_from:
      file: "${recipe_dir}/data.yaml"
      path: "options"  # YAML path to choices array
      
  multi_dynamic:
    prompt: "Select multiple:"
    type: "multi_choice"
    choices_from:
      file: "${recipe_dir}/catalog.yaml"
      path: "items"
      id_field: "key"        # Field to use as choice ID
      label_field: "display" # Field to use as label
      default_field: "default" # Optional: field for default state
```

When using `choices_from`, the setup command:
1. Loads the specified YAML/JSON file
2. Extracts choices from the specified path
3. Maps fields to choice structure
4. Presents to user as normal

## Step Types

### check_file
Check if file exists. If `if_exists: "ask_backup"`, prompt user to backup.

### copy_template
Copy from recipe directory to target location. Create backup if file exists and backup: true.

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
6. **Always present choices with numbered lists for easy selection**

## Error Handling

- If template file missing: Show error and suggest checking setup directory
- If write fails: Offer to retry with sudo or different location
- If recipe not found: List available recipes
- Always provide manual instructions as fallback

## Example Session

```
Human: /setup
Assistant: I'll check for the setup directory in the following locations:
- .claude/setup/ (project-specific)
- $CLAUDE_CONFIG_DIR/setup/ (custom config)
- ~/.claude/setup/ (default)

Found setup directory at: $CLAUDE_CONFIG_DIR/setup

🛠️  Claude Code Setup Assistant
Configure your project with Claude Code best practices

1. MCP Servers - Configure Model Context Protocol
2. Command Guards - Safety hooks for commands
3. CLAUDE.md - Project documentation for Claude
4. All Recommended - Complete setup

Enter your choice (1-4) or 'q' to quit: 
```

## Recipe Extensibility

Recipes can extend functionality using helper scripts and assets:

### Helper Scripts Pattern
```yaml
steps:
  - name: "Complex processing"
    type: "run_command"
    config:
      command: "${recipe_dir}/helpers/process-config.sh"
      args: ["${variable1}", "${variable2}", "${output_path}"]
      working_dir: "${recipe_dir}"
```

### Recipe Structure Convention
```
recipes/recipe-name/
├── recipe.yaml              # Recipe definition
├── helpers/                 # Helper scripts (optional)
│   ├── generate-config.sh   # Executable helper script
│   └── validate-setup.py    # Can use any language
├── templates/               # Template files (optional)
│   └── config.template      # Static templates
└── assets/                  # Other recipe assets
    └── data.yaml           # Supporting data files
```

### Guidelines
- Keep complex logic in helper scripts, not in setup command
- Use `run_command` step type to execute recipe-specific tools
- Pass variables as command line arguments to helpers
- Helper scripts should be executable and self-contained

## Implementation Note

When this command runs, follow these steps:

1. First check if `.claude/setup/menu.yaml` exists in the current project
2. If not found and `CLAUDE_CONFIG_DIR` is set, check `$CLAUDE_CONFIG_DIR/setup/menu.yaml`
3. If still not found, check `~/.claude/setup/menu.yaml`
4. Use the first valid setup directory found

This ensures proper precedence:
- Project overrides (`.claude/setup/`)
- User custom config (`$CLAUDE_CONFIG_DIR/setup/`)
- Default location (`~/.claude/setup/`)

If no setup directory is found, provide helpful error message with expected locations.