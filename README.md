# kiro-skills

🛠️ Personal Kiro user-scope configuration — skills, steering, and project context for full-stack cloud development.

## What's Inside

- **7 Steering files** — coding rules auto-applied by file type
- **29 Skills** — domain expertise loaded on-demand via [agentskills.io](https://agentskills.io) spec

### Steering (always/fileMatch)

| File | Trigger | Scope |
|------|---------|-------|
| docker-rules.md | `Dockerfile*,docker-compose*` | Docker Rules |
| gitlab-ci-rules.md | `.gitlab-ci*` | GitLab CI Rules |
| k8s-helm-rules.md | `**/k8s/**/*.yaml,**/k8s/**/*.yml,**/helm/**/*.yaml,**/helm/**/*.yml,**/charts/**/*.yaml,**/charts/**/*.yml,**/manifests/**/*.yaml,**/manifests/**/*.yml,**/deploy/**/*.yaml,**/deploy/**/*.yml,**/templates/**/*.yaml` | Kubernetes / Helm Rules |
| personal-preferences.md | always | Personal Preferences |
| sql-rules.md | `*.sql,*migration*` | SQL Rules |
| typescript-rules.md | `*.ts,*.tsx,*.js,*.jsx` | TypeScript/JavaScript Rules |
| user-scope-config.example.md | always | User Scope Config (EXAMPLE) |

### Skills by Category

**AWS & Cloud**

- `api-gateway` — >
- `aws-agentic-ai` — AWS Bedrock AgentCore comprehensive expert for deploying and managing AI agents at scale. Use when working with any AgentCore service including Gateway, Runtime, Memory, Identity, Code Interpreter, Browser, Observability, Agent Registry, or Evaluations. Covers agent deployment, MCP tool integration, credential management, agent discovery, governance workflows, and automated quality assessment. Essential when user mentions AgentCore, agent runtime, agent registry, agent evaluation, MCP gateway, deploy agent, register MCP server, discover agents, evaluate agent quality, agent credentials, or wants to build, deploy, catalog, or monitor AI agents on AWS.
- `aws-cdk-development` — AWS Cloud Development Kit (CDK) expert for building cloud infrastructure with TypeScript/Python. Use when creating CDK stacks, defining CDK constructs, implementing infrastructure as code, or when the user mentions CDK, CloudFormation, IaC, cdk synth, cdk deploy, or wants to define AWS infrastructure programmatically. Covers CDK app structure, construct patterns, stack composition, and deployment workflows.
- `aws-cost-operations` — AWS cost optimization, monitoring, and operational excellence expert. Use when analyzing AWS bills, estimating costs, setting up CloudWatch alarms, querying logs, auditing CloudTrail activity, or assessing security posture. Essential when user mentions AWS costs, spending, billing, budget, pricing, CloudWatch, observability, monitoring, alerting, CloudTrail, audit, or wants to optimize AWS infrastructure costs and operational efficiency.
- `aws-lambda` — "Design, build, deploy, test, and debug serverless applications with AWS Lambda. Triggers on phrases like: Lambda function, event source, serverless application, API Gateway, EventBridge, Step Functions, serverless API, event-driven architecture, Lambda trigger. For deploying non-serverless apps to AWS, use deploy-on-aws plugin instead."
- `aws-lambda-durable-functions` — >
- `aws-mcp-setup` — Configure AWS MCP servers for documentation search and API access. Use when setting up AWS MCP, configuring AWS documentation tools, troubleshooting MCP connectivity, or when user mentions aws-mcp, awsdocs, uvx setup, or MCP server configuration. Covers both Full AWS MCP Server (with uvx + credentials) and lightweight Documentation MCP (no auth required).
- `aws-serverless-deployment` — "AWS SAM and AWS CDK deployment for serverless applications. Triggers on phrases like: use SAM, SAM template, SAM init, SAM deploy, CDK serverless, CDK Lambda construct, NodejsFunction, PythonFunction, SAM and CDK together, serverless CI/CD pipeline. For general app deployment with service selection, use deploy-on-aws plugin instead."
- `aws-serverless-eda` — AWS serverless and event-driven architecture expert based on Well-Architected Framework. Use when building serverless APIs, Lambda functions, REST APIs, microservices, or async workflows. Covers Lambda with TypeScript/Python, API Gateway (REST/HTTP), DynamoDB, Step Functions, EventBridge, SQS, SNS, and serverless patterns. Essential when user mentions serverless, Lambda, API Gateway, event-driven, async processing, queues, pub/sub, or wants to build scalable serverless applications with AWS best practices.
- `supabase-postgres` — Postgres performance optimization and best practices from Supabase. Use this skill when writing, reviewing, or optimizing Postgres queries, schema designs, or database configurations.

**Platform & Infra**

- `docker-container`
- `gitops-cicd`
- `helm-charts`
- `k8s-eks`
- `observability`

**Data & Messaging**

- `dynamodb`
- `elasticsearch-opensearch`
- `iot-messaging`
- `kafka-msk`
- `rdb-optimization`

**Development**

- `api-design`
- `architecture`
- `git-gitlab`
- `typescript-node`

**Workflow & Management**

- `jira-workflow`
- `knowledge-publish`
- `project-context-manager`
- `scope-manager`
- `skill-creator` — Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description for better triggering accuracy.

## Installation

```bash
git clone https://github.com/shyswy/kiro-skills.git ~/.kiro-repo

# Symlink or copy to ~/.kiro
ln -sf ~/.kiro-repo/steering/* ~/.kiro/steering/
ln -sf ~/.kiro-repo/skills/* ~/.kiro/skills/
```

Or if this IS your `~/.kiro` directory:

```bash
cd ~/.kiro
git init
git remote add origin https://github.com/shyswy/kiro-skills.git
git pull origin main
```

## Structure

```
~/.kiro/
├── steering/           # Steering files (auto-loaded by file type)
│   ├── typescript-rules.md      # Public (pushed to git)
│   └── _user-scope-config.md   # Private (gitignored)
├── skills/             # Skills (loaded on-demand by trigger keywords)
│   ├── kafka-msk/               # Public
│   └── _sprint-worklog-manager/ # Private (gitignored)
├── projects/           # Project context (managed by project-context-manager)
├── scripts/            # Automation scripts
└── settings/           # MCP configs (gitignored, contains secrets)
```

## Private Convention

Files/directories starting with `_` (underscore) are **private** — they are gitignored and never pushed to the public repo.

| Type | Public | Private |
|------|--------|---------|
| Skill | `skills/kafka-msk/` | `skills/_sprint-worklog-manager/` |
| Steering | `steering/typescript-rules.md` | `steering/_user-scope-config.md` |

**When to make something private:**
- Contains company URLs, internal project names, or team-specific workflows
- References internal tools, tokens, or infrastructure details
- Only useful within your specific organization

**How to add a private skill/steering:**
Just prefix the name with `_`. No gitignore edits needed — the pattern `skills/_*/` and `steering/_*.md` covers everything automatically.

## Customization

Copy `steering/user-scope-config.example.md` to `steering/_user-scope-config.md` and fill in your environment details. Use the `scope-manager` skill for guided updates.

## Auto-indexing

When a new skill is added, run:
```bash
bash scripts/update-skills-index.sh
```
Or it runs automatically via the `skill-index-updater` hook when SKILL.md files are created.

## License

MIT — see [LICENSE](LICENSE)

## Attribution

See [ATTRIBUTION.md](ATTRIBUTION.md) for all referenced sources.
