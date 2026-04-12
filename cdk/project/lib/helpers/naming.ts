/**
 * Generate a resource name following the convention: <ProjectName>-<Environment>-<identifier>
 * Do NOT include AWS service names in the identifier.
 */
export function resourceName(projectName: string, environment: string, identifier: string): string {
  return `${projectName}-${environment}-${identifier}`;
}
