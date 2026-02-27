## Azure IaC / Bicep Authoring Instructions for Copilot

You are assisting with Azure Infrastructure-as-Code development using **Bicep**, **PowerShell**, and **Azure CLI**. Follow these rules strictly:

### 1. Bicep Authoring Rules
- Use **valid Azure resource types and API versions** that exist in Azure today.
- Never invent or guess API versions or resource types.
- Prefer **latest stable API versions** unless instructed otherwise.
- Use correct Bicep syntax: `resource`, `param`, `var`, `output`, `existing`, `scope`.
- When generating modules:
  - Include clear parameters with types.
  - Include outputs only when useful.
  - Avoid unnecessary variables.
  - Use consistent naming conventions.

### 2. Azure Deployment Patterns
- Use correct deployment scopes:
  - `az deployment group create` for resource groups
  - `az deployment sub create` for subscription deployments
  - `az deployment mg create` for management group deployments
- Include example commands for deploying the generated Bicep file.
- Never invent CLI flags or PowerShell cmdlets.
- Include related objects in the same Bicep file when relevant (e.g., NSG rules with NSG, subnets with VNet).

### 3. PowerShell Rules
- Produce **literal, deterministic PowerShell**.
- Avoid aliases (`ls`, `gc`, `ni`, etc.).
- Use full cmdlet names.
- Use `-ErrorAction Stop` for reliability.
- Avoid unnecessary complexity.
- Add explicit module imports if needed (e.g., `Import-Module Az`).
- Verify the cmdlets exist in the specific module version before suggesting them.

### 4. Output Format
When I ask for code:
- Use separate code blocks for Bicep, PowerShell, and CLI.
- Keep code clean, minimal, and production-ready.
- comply with the latest best practices for Azure IaC and scripting.
- inclue verbose output and error handling in scripts.
- include error handling in deployment commands (e.g., `--only-show-errors` for CLI).
- include data validation in PowerShell (e.g., parameter checks, try/catch).

### 5. Behavior Expectations
- If my request is ambiguous, ask clarifying questions.
- If the request is clear, generate the code directly.
- Do not hallucinate Azure features or syntax.
- Prefer correctness over creativity.
- Prefer simplicity over complexity.
- Recognize that this is all intended for learning and experimentation, so it's okay to produce code that is not fully production-hardened, but it should still follow best practices and be free of errors.
- This project is focused on a demonstration of a new architecture for learning and experimentation, so prioritize: readability and speed of deployment, and reproducibility of results, over extensible and maintainable code. 
- Optimize speed and the ability to demonstrate results quickly over production-ready code
- Produced Azure objects should be valid and deployable, but they do not need to be fully optimized for cost or performance, as the focus is on learning and experimentation.



### 6. Example Response Structure
When generating IaC, follow this structure:

1. **Short explanation** (2–3 sentences max)
2. **Bicep module** (code block)
3. **Deployment command** (PowerShell or CLI)
4. **Optional notes** (only if needed)

---

### Context for This Project
This repository is used for:
- Deploying Azure core resources using Bicep and PowerShell
- Reproducing a SIMPLIFIED version of an on premises DNS migration architecture in Azure
- Demonstrating the required actions and impact of a migration to Private DNS in Azure


Always optimize for clarity, correctness, and maintainability.