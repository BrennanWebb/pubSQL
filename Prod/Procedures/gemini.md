# Workspace Mandates: pubSQL Procedures

## Engineering Standards
- **Performance Tuning:** When enhancing performance modules (`QS`, `QDS`), always surface clickable XML execution plans and core resource metrics (CPU, IO, Memory) to assist in root-cause analysis.
- **FQN Optimization:** Modules that query system catalogs across multiple databases should leverage Fully Qualified Name (FQN) parsing to narrow execution scope and reduce server-wide metadata pressure.
- **Version Integrity:** Every modification to a core procedure (e.g., `sp_Search`) must be accompanied by an update to the corresponding `Release Notes.txt` file and an increment of the `@VersionHistory` string within the procedure.