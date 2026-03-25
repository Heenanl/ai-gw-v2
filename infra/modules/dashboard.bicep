// Azure Portal Dashboard for APIM AI Gateway - Quota Monitoring
// Uses ApiManagementGatewayLlmLog as primary source (reliable, not sampled)
// Joined with ApiManagementGatewayLogs for caller identification via x-caller-name header

@description('Location for the dashboard')
param location string

@description('Log Analytics Workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Quota configuration JSON string (for reference panel)')
param quotaConfig string = '{}'

var dashboardName = 'apim-quota-dashboard-${toLower(uniqueString(resourceGroup().id, location))}'

// KQL: Monthly token usage per caller
var kqlQuotaOverview = '''
let callerLogs = ApiManagementGatewayLogs
| where ResponseHeaders has "x-caller-name"
| extend CallerName = extract(@'"x-caller-name":"([^"]+)"', 1, tostring(ResponseHeaders))
| summarize CallerName = take_any(CallerName) by CorrelationId;
ApiManagementGatewayLlmLog
| where TimeGenerated >= startofmonth(now())
| join kind=leftouter callerLogs on CorrelationId
| summarize
    MonthlyTokens = sum(TotalTokens),
    PromptTokens = sum(PromptTokens),
    CompletionTokens = sum(CompletionTokens),
    Requests = dcount(CorrelationId)
    by CallerName
| project CallerName, MonthlyTokens, PromptTokens, CompletionTokens, Requests
| order by MonthlyTokens desc
'''

// KQL: Hourly token usage by caller
var kqlTokenUsageOverTime = '''
let callerLogs = ApiManagementGatewayLogs
| where ResponseHeaders has "x-caller-name"
| extend CallerName = extract(@'"x-caller-name":"([^"]+)"', 1, tostring(ResponseHeaders))
| summarize CallerName = take_any(CallerName) by CorrelationId;
ApiManagementGatewayLlmLog
| where DeploymentName != ""
| join kind=leftouter callerLogs on CorrelationId
| summarize TotalTokens = sum(TotalTokens) by bin(TimeGenerated, 1h), CallerName
| order by TimeGenerated asc
'''

// KQL: Rate limit events (429s per caller)
var kqlRateLimitEvents = '''
ApiManagementGatewayLogs
| where ResponseCode == 429
| extend CallerName = coalesce(
    extract(@'"x-caller-name":"([^"]+)"', 1, tostring(ResponseHeaders)),
    extract(@'"x-caller-name":"([^"]+)"', 1, tostring(BackendRequestHeaders))
  )
| summarize
    ThrottledRequests = count(),
    FirstThrottle = min(TimeGenerated),
    LastThrottle = max(TimeGenerated)
    by CallerName
| order by ThrottledRequests desc
'''

// KQL: Model usage by caller
var kqlModelUsageByCaller = '''
let callerLogs = ApiManagementGatewayLogs
| where ResponseHeaders has "x-caller-name"
| extend CallerName = extract(@'"x-caller-name":"([^"]+)"', 1, tostring(ResponseHeaders))
| summarize CallerName = take_any(CallerName) by CorrelationId;
ApiManagementGatewayLlmLog
| where DeploymentName != ""
| join kind=leftouter callerLogs on CorrelationId
| summarize
    PromptTokens = sum(PromptTokens),
    CompletionTokens = sum(CompletionTokens),
    TotalTokens = sum(TotalTokens),
    Requests = dcount(CorrelationId)
by CallerName, DeploymentName, ModelName
| order by CallerName asc, TotalTokens desc
'''

// KQL: Daily usage by caller
var kqlDailyUsageByCaller = '''
let callerLogs = ApiManagementGatewayLogs
| where ResponseHeaders has "x-caller-name"
| extend CallerName = extract(@'"x-caller-name":"([^"]+)"', 1, tostring(ResponseHeaders))
| summarize CallerName = take_any(CallerName) by CorrelationId;
ApiManagementGatewayLlmLog
| join kind=leftouter callerLogs on CorrelationId
| summarize
    TotalTokens = sum(TotalTokens),
    PromptTokens = sum(PromptTokens),
    CompletionTokens = sum(CompletionTokens),
    Requests = dcount(CorrelationId)
by bin(TimeGenerated, 1d), CallerName
| order by TimeGenerated desc, TotalTokens desc
'''

// KQL: Error breakdown (4xx/5xx by caller)
var kqlErrorBreakdown = '''
ApiManagementGatewayLogs
| where ResponseCode >= 400
| extend CallerName = coalesce(
    extract(@'"x-caller-name":"([^"]+)"', 1, tostring(ResponseHeaders)),
    extract(@'"x-caller-name":"([^"]+)"', 1, tostring(BackendRequestHeaders))
  )
| summarize Count = count() by ResponseCode, CallerName, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
'''

// KQL: Monthly cumulative token burn-down
var kqlMonthlyBurnDown = '''
let callerLogs = ApiManagementGatewayLogs
| where ResponseHeaders has "x-caller-name"
| extend CallerName = extract(@'"x-caller-name":"([^"]+)"', 1, tostring(ResponseHeaders))
| summarize CallerName = take_any(CallerName) by CorrelationId;
ApiManagementGatewayLlmLog
| where TimeGenerated >= startofmonth(now())
| join kind=leftouter callerLogs on CorrelationId
| summarize CumulativeTokens = sum(TotalTokens) by CallerName, bin(TimeGenerated, 1h)
| order by CallerName, TimeGenerated asc
| serialize
| extend RunningTotal = row_cumsum(CumulativeTokens, CallerName != prev(CallerName))
'''

resource dashboard 'Microsoft.Portal/dashboards@2022-12-01-preview' = {
  name: dashboardName
  location: location
  tags: {
    'hidden-title': 'AI Gateway - Quota Dashboard'
  }
  properties: {
    lenses: [
      {
        order: 0
        parts: [
          // Title
          {
            position: { x: 0, y: 0, colSpan: 17, rowSpan: 2 }
            metadata: any({
              type: 'Extension/HubsExtension/PartType/MarkdownPart'
              inputs: []
              settings: {
                content: {
                  content: '# AI Gateway - Quota Dashboard\n\nMonitor per-caller token usage, quota consumption, and rate limit events.\n\nData sourced from `ApiManagementGatewayLlmLog` joined with `ApiManagementGatewayLogs` for caller identification.'
                  title: ''
                  subtitle: ''
                  markdownSource: 1
                }
              }
            })
          }
          // Quota Overview (grid)
          {
            position: { x: 0, y: 2, colSpan: 17, rowSpan: 4 }
            metadata: any({
              type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
              inputs: [
                { name: 'Scope', value: { resourceIds: [ logAnalyticsWorkspaceId ] }, isOptional: true }
                { name: 'Version', value: '2.0', isOptional: true }
                { name: 'TimeRange', value: 'P30D', isOptional: true }
                { name: 'PartId', value: 'quota-overview', isOptional: true }
                { name: 'PartTitle', value: 'Caller Quota Overview (This Month)', isOptional: true }
                { name: 'PartSubTitle', value: 'Monthly token usage per caller', isOptional: true }
                { name: 'Query', value: kqlQuotaOverview, isOptional: true }
                { name: 'ControlType', value: 'AnalyticsGrid', isOptional: true }
                { name: 'resourceTypeMode', isOptional: true }
                { name: 'ComponentId', isOptional: true }
                { name: 'DashboardId', isOptional: true }
                { name: 'DraftRequestParameters', isOptional: true }
                { name: 'SpecificChart', isOptional: true }
                { name: 'Dimensions', isOptional: true }
                { name: 'LegendOptions', isOptional: true }
                { name: 'IsQueryContainTimeRange', isOptional: true }
              ]
              settings: {}
            })
          }
          // Token Usage Over Time (stacked chart)
          {
            position: { x: 0, y: 6, colSpan: 17, rowSpan: 5 }
            metadata: any({
              type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
              inputs: [
                { name: 'Scope', value: { resourceIds: [ logAnalyticsWorkspaceId ] }, isOptional: true }
                { name: 'Version', value: '2.0', isOptional: true }
                { name: 'TimeRange', value: 'P7D', isOptional: true }
                { name: 'PartId', value: 'usage-over-time', isOptional: true }
                { name: 'PartTitle', value: 'Token Usage Over Time by Caller', isOptional: true }
                { name: 'PartSubTitle', value: 'Hourly token consumption', isOptional: true }
                { name: 'Query', value: kqlTokenUsageOverTime, isOptional: true }
                { name: 'ControlType', value: 'AnalyticsGrid', isOptional: true }
                { name: 'resourceTypeMode', isOptional: true }
                { name: 'ComponentId', isOptional: true }
                { name: 'DashboardId', isOptional: true }
                { name: 'DraftRequestParameters', isOptional: true }
                { name: 'SpecificChart', isOptional: true }
                { name: 'Dimensions', isOptional: true }
                { name: 'LegendOptions', isOptional: true }
                { name: 'IsQueryContainTimeRange', isOptional: true }
              ]
              settings: {
                content: {
                  Query: '${kqlTokenUsageOverTime}\n'
                  ControlType: 'FrameControlChart'
                  SpecificChart: 'StackedColumn'
                  Dimensions: {
                    xAxis: { name: 'TimeGenerated', type: 'datetime' }
                    yAxis: [ { name: 'TotalTokens', type: 'long' } ]
                    splitBy: [ { name: 'CallerName', type: 'string' } ]
                    aggregation: 'Sum'
                  }
                  LegendOptions: { isEnabled: true, position: 'Bottom' }
                }
              }
            })
          }
          // Rate Limit Events (grid, left)
          {
            position: { x: 0, y: 11, colSpan: 8, rowSpan: 4 }
            metadata: any({
              type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
              inputs: [
                { name: 'Scope', value: { resourceIds: [ logAnalyticsWorkspaceId ] }, isOptional: true }
                { name: 'Version', value: '2.0', isOptional: true }
                { name: 'TimeRange', value: 'P7D', isOptional: true }
                { name: 'PartId', value: 'rate-limits', isOptional: true }
                { name: 'PartTitle', value: 'Rate Limit Events (429)', isOptional: true }
                { name: 'PartSubTitle', value: 'Throttled requests by caller', isOptional: true }
                { name: 'Query', value: kqlRateLimitEvents, isOptional: true }
                { name: 'ControlType', value: 'AnalyticsGrid', isOptional: true }
                { name: 'resourceTypeMode', isOptional: true }
                { name: 'ComponentId', isOptional: true }
                { name: 'DashboardId', isOptional: true }
                { name: 'DraftRequestParameters', isOptional: true }
                { name: 'SpecificChart', isOptional: true }
                { name: 'Dimensions', isOptional: true }
                { name: 'LegendOptions', isOptional: true }
                { name: 'IsQueryContainTimeRange', isOptional: true }
              ]
              settings: {}
            })
          }
          // Error Breakdown (grid, right)
          {
            position: { x: 8, y: 11, colSpan: 9, rowSpan: 4 }
            metadata: any({
              type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
              inputs: [
                { name: 'Scope', value: { resourceIds: [ logAnalyticsWorkspaceId ] }, isOptional: true }
                { name: 'Version', value: '2.0', isOptional: true }
                { name: 'TimeRange', value: 'P7D', isOptional: true }
                { name: 'PartId', value: 'error-breakdown', isOptional: true }
                { name: 'PartTitle', value: 'Error Breakdown', isOptional: true }
                { name: 'PartSubTitle', value: 'HTTP errors (4xx/5xx) by caller and status code', isOptional: true }
                { name: 'Query', value: kqlErrorBreakdown, isOptional: true }
                { name: 'ControlType', value: 'AnalyticsGrid', isOptional: true }
                { name: 'resourceTypeMode', isOptional: true }
                { name: 'ComponentId', isOptional: true }
                { name: 'DashboardId', isOptional: true }
                { name: 'DraftRequestParameters', isOptional: true }
                { name: 'SpecificChart', isOptional: true }
                { name: 'Dimensions', isOptional: true }
                { name: 'LegendOptions', isOptional: true }
                { name: 'IsQueryContainTimeRange', isOptional: true }
              ]
              settings: {}
            })
          }
          // Model Usage by Caller (grid)
          {
            position: { x: 0, y: 15, colSpan: 17, rowSpan: 4 }
            metadata: any({
              type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
              inputs: [
                { name: 'Scope', value: { resourceIds: [ logAnalyticsWorkspaceId ] }, isOptional: true }
                { name: 'Version', value: '2.0', isOptional: true }
                { name: 'TimeRange', value: 'P30D', isOptional: true }
                { name: 'PartId', value: 'model-by-caller', isOptional: true }
                { name: 'PartTitle', value: 'Model Usage by Caller', isOptional: true }
                { name: 'PartSubTitle', value: 'Token consumption per deployment/model by caller', isOptional: true }
                { name: 'Query', value: kqlModelUsageByCaller, isOptional: true }
                { name: 'ControlType', value: 'AnalyticsGrid', isOptional: true }
                { name: 'resourceTypeMode', isOptional: true }
                { name: 'ComponentId', isOptional: true }
                { name: 'DashboardId', isOptional: true }
                { name: 'DraftRequestParameters', isOptional: true }
                { name: 'SpecificChart', isOptional: true }
                { name: 'Dimensions', isOptional: true }
                { name: 'LegendOptions', isOptional: true }
                { name: 'IsQueryContainTimeRange', isOptional: true }
              ]
              settings: {}
            })
          }
          // Daily Usage by Caller (grid)
          {
            position: { x: 0, y: 19, colSpan: 17, rowSpan: 4 }
            metadata: any({
              type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
              inputs: [
                { name: 'Scope', value: { resourceIds: [ logAnalyticsWorkspaceId ] }, isOptional: true }
                { name: 'Version', value: '2.0', isOptional: true }
                { name: 'TimeRange', value: 'P30D', isOptional: true }
                { name: 'PartId', value: 'daily-usage', isOptional: true }
                { name: 'PartTitle', value: 'Daily Usage by Caller', isOptional: true }
                { name: 'PartSubTitle', value: 'Daily token breakdown', isOptional: true }
                { name: 'Query', value: kqlDailyUsageByCaller, isOptional: true }
                { name: 'ControlType', value: 'AnalyticsGrid', isOptional: true }
                { name: 'resourceTypeMode', isOptional: true }
                { name: 'ComponentId', isOptional: true }
                { name: 'DashboardId', isOptional: true }
                { name: 'DraftRequestParameters', isOptional: true }
                { name: 'SpecificChart', isOptional: true }
                { name: 'Dimensions', isOptional: true }
                { name: 'LegendOptions', isOptional: true }
                { name: 'IsQueryContainTimeRange', isOptional: true }
              ]
              settings: {}
            })
          }
          // Monthly Burn-Down (line chart)
          {
            position: { x: 0, y: 23, colSpan: 17, rowSpan: 5 }
            metadata: any({
              type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
              inputs: [
                { name: 'Scope', value: { resourceIds: [ logAnalyticsWorkspaceId ] }, isOptional: true }
                { name: 'Version', value: '2.0', isOptional: true }
                { name: 'TimeRange', value: 'P30D', isOptional: true }
                { name: 'PartId', value: 'budget-burndown', isOptional: true }
                { name: 'PartTitle', value: 'Monthly Token Burn-Down by Caller', isOptional: true }
                { name: 'PartSubTitle', value: 'Cumulative token usage this month', isOptional: true }
                { name: 'Query', value: kqlMonthlyBurnDown, isOptional: true }
                { name: 'ControlType', value: 'AnalyticsGrid', isOptional: true }
                { name: 'resourceTypeMode', isOptional: true }
                { name: 'ComponentId', isOptional: true }
                { name: 'DashboardId', isOptional: true }
                { name: 'DraftRequestParameters', isOptional: true }
                { name: 'SpecificChart', isOptional: true }
                { name: 'Dimensions', isOptional: true }
                { name: 'LegendOptions', isOptional: true }
                { name: 'IsQueryContainTimeRange', isOptional: true }
              ]
              settings: {
                content: {
                  Query: '${kqlMonthlyBurnDown}\n'
                  ControlType: 'FrameControlChart'
                  SpecificChart: 'Line'
                  Dimensions: {
                    xAxis: { name: 'TimeGenerated', type: 'datetime' }
                    yAxis: [ { name: 'RunningTotal', type: 'long' } ]
                    splitBy: [ { name: 'CallerName', type: 'string' } ]
                    aggregation: 'Sum'
                  }
                  LegendOptions: { isEnabled: true, position: 'Bottom' }
                }
              }
            })
          }
          // Quota Config Reference
          {
            position: { x: 0, y: 28, colSpan: 17, rowSpan: 2 }
            metadata: any({
              type: 'Extension/HubsExtension/PartType/MarkdownPart'
              inputs: []
              settings: {
                content: {
                  content: '## Quota Configuration\n\nCurrent mapping (from APIM Named Value `quota-config`):\n```json\n${quotaConfig}\n```'
                  title: ''
                  subtitle: ''
                  markdownSource: 1
                }
              }
            })
          }
        ]
      }
    ]
    metadata: {
      model: {
        timeRange: {
          value: {
            relative: {
              duration: 24
              timeUnit: 1
            }
          }
          type: 'MsPortalFx.Composition.Configuration.ValueTypes.TimeRange'
        }
        filterLocale: { value: 'en-us' }
        filters: {
          value: {
            MsPortalFx_TimeRange: {
              model: { format: 'utc', granularity: 'auto', relative: '7d' }
              displayCache: { name: 'UTC Time', value: 'Past 7 days' }
            }
          }
        }
      }
    }
  }
}

output dashboardId string = dashboard.id
