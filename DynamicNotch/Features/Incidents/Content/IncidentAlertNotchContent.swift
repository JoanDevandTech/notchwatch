import NotchwatchCore
import SwiftUI

/// Tarjeta temporal de una incidencia recién llegada. Un clic la abre en la fuente.
struct IncidentAlertNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.Incidents.alert.id

    let incidentsViewModel: IncidentsViewModel
    let incident: Incident
    /// Cuántas más llegaron en la misma tanda.
    let extra: Int

    var priority: Int { NotchContentRegistry.Incidents.alert.priority }
    var isRestorable: Bool { false }

    /// Un clic en la tarjeta despliega la lista (el gesto del motor también alcanza a los botones
    /// de la tarjeta, así que «Abrir» abre Asana y además despliega).
    var windowLink: (@MainActor () -> Void)? {
        { [incidentsViewModel, incident] in
            incidentsViewModel.acknowledge(incident)
            incidentsViewModel.requestExpand()
        }
    }

    var strokeColor: Color {
        IncidentsStrokePalette.color(
            for: .attention(incident.priority),
            appearance: incidentsViewModel.profile.appearance
        )
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        IncidentsLayout.alertSize(baseWidth: baseWidth, baseHeight: baseHeight, isNotchless: false)
    }

    func dynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        IncidentsLayout.alertSize(baseWidth: baseWidth, baseHeight: baseHeight, isNotchless: true)
    }

    func cornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        IncidentsLayout.alertCornerRadius
    }

    func dynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        min(baseHeight * 0.5, IncidentsLayout.alertCornerRadius.bottom)
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(
            IncidentAlertView(
                viewModel: incidentsViewModel,
                incident: incident,
                extra: extra,
                onExpand: { [incidentsViewModel] in
                    incidentsViewModel.requestExpand()
                }
            )
        )
    }
}
