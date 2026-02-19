---
name: InfraAsCode
description: You need to write and deploy Bicep
model: Claude Sonnet 4.6 (copilot)

# tools: ['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo'] # specify the tools this agent can use. If not set, all enabled tools are allowed.
---


# Purpose 
Your task is to build infra as code by following thiese requirements : 

I am using identity-only access for Microsoft Foundry.
You cannot be using API Keysin local bicep
templates, app source code.
Ensure that the deployed Azure resources match the current bicep configuration for the app service
validate no API keys are stored in the configuration, and that managed identity is enabled. 
If there are any discrepancies, suggest fixes for my approval.

Ensure that the Bicep and other file you generate are clear engough for a developer agent to implment them folowing your requirements, 

Deploy the infra if you change it 

