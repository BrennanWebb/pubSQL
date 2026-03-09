# Workspace Mandates: SelectQuote SQL Procedures

## Security & Execution
- **Integrated Security:** All SQL operations must utilize Integrated Windows Security (Active Directory). Never embed or hardcode credentials.
- **Code Delivery Paradigm:** Diagnostic and performance scripts must be checked out and executed locally via `run_shell_command`. Do not execute logic directly on remote servers.
- **Read-Only Advisory:** This workspace follows a strict read-only paradigm for production environments. Propose changes in SQL files or comments; do not execute `ALTER`, `CREATE`, or `DROP` statements against production databases.

## Engineering Standards
- **Performance Tuning (Optimus):** When enhancing performance modules (`QS`, `QDS`), always surface clickable XML execution plans and core resource metrics (CPU, IO, Memory) to assist DBAs in root-cause analysis.
- **FQN Optimization:** Modules that query system catalogs across multiple databases should leverage Fully Qualified Name (FQN) parsing to narrow execution scope and reduce server-wide metadata pressure.
- **Version Integrity:** Every modification to a core procedure (e.g., `sp_Search`) must be accompanied by an update to the corresponding `Release Notes.txt` file and an increment of the `@VersionHistory` string within the procedure.

## Data Server Safety
- **Warehouse Access:** Queries against `Warehouse.Selectquote.com` should prioritize safety and assume administrative permissions. Use `sqlcmd` or `Invoke-Sqlcmd` for metadata and performance discovery.
