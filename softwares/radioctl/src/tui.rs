use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Tabs, Wrap},
    Frame,
};

use crate::{
    app::{Application, Overlay, Pane},
    domain::{
        ActivityLevel, BackendHealth, BluetoothDevice, ConnectionState, Connectivity, WifiNetwork,
    },
};

const ACCENT: Color = Color::Cyan;
const SELECTED_BG: Color = Color::Rgb(35, 48, 60);

pub fn draw(frame: &mut Frame<'_>, app: &mut Application) {
    let area = frame.size();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(2),
            Constraint::Length(3),
            Constraint::Min(4),
            Constraint::Length(if app.reducer.state.current_error.is_some() {
                3
            } else {
                1
            }),
            Constraint::Length(1),
        ])
        .split(area);

    draw_header(frame, chunks[0], app);
    draw_tabs(frame, chunks[1], app);

    let content = if chunks[2].width >= 100 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(65), Constraint::Percentage(35)])
            .split(chunks[2])
    } else {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(100), Constraint::Length(0)])
            .split(chunks[2])
    };
    draw_list(frame, content[0], app);
    if content[1].width > 0 {
        draw_details(frame, content[1], app);
    }
    draw_notification(frame, chunks[3], app);
    draw_footer(frame, chunks[4], app);

    match app.overlay {
        Some(Overlay::Help) => draw_help(frame, area),
        Some(Overlay::Activity) => draw_activity(frame, area, app),
        Some(Overlay::Palette) => draw_palette(frame, area, app),
        Some(Overlay::Search) => draw_search(frame, area, app),
        None => {}
    }
}

fn draw_header(frame: &mut Frame<'_>, area: Rect, app: &Application) {
    let backend_text = if app.reducer.state.backends.is_empty() {
        Span::styled("probing services", Style::default().fg(Color::Yellow))
    } else {
        let ready = app
            .reducer
            .state
            .backends
            .values()
            .filter(|backend| backend.health == BackendHealth::Ready)
            .count();
        Span::styled(
            format!(
                "{ready}/{} services ready",
                app.reducer.state.backends.len()
            ),
            Style::default().fg(if ready == 0 {
                Color::Yellow
            } else {
                Color::Green
            }),
        )
    };
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(
                "radioctl",
                Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
            ),
            Span::raw("  "),
            backend_text,
            Span::styled(
                format!("  {} events", app.reducer.state.activity.len()),
                Style::default().fg(Color::DarkGray),
            ),
        ])),
        area,
    );
}

fn draw_tabs(frame: &mut Frame<'_>, area: Rect, app: &Application) {
    let selected = usize::from(app.pane == Pane::Bluetooth);
    let tabs = Tabs::new(["1 Wi-Fi", "2 Bluetooth"])
        .select(selected)
        .block(Block::default().borders(Borders::ALL))
        .highlight_style(
            Style::default()
                .fg(Color::Black)
                .bg(ACCENT)
                .add_modifier(Modifier::BOLD),
        );
    frame.render_widget(tabs, area);
}

fn draw_list(frame: &mut Frame<'_>, area: Rect, app: &mut Application) {
    match app.pane {
        Pane::Wifi => {
            let ids = app.visible_wifi_ids();
            let rows = ids
                .iter()
                .map(|id| wifi_row(&app.reducer.state.wifi.networks[id]))
                .collect::<Vec<_>>();
            let selected = app
                .reducer
                .state
                .wifi
                .selected
                .as_ref()
                .and_then(|selected| ids.iter().position(|id| id == selected));
            render_list(frame, area, " Wi-Fi networks ", rows, selected);
        }
        Pane::Bluetooth => {
            let ids = app.visible_bluetooth_ids();
            let rows = ids
                .iter()
                .map(|id| bluetooth_row(&app.reducer.state.bluetooth.devices[id]))
                .collect::<Vec<_>>();
            let selected = app
                .reducer
                .state
                .bluetooth
                .selected
                .as_ref()
                .and_then(|selected| ids.iter().position(|id| id == selected));
            render_list(frame, area, " Bluetooth devices ", rows, selected);
        }
    }
    app.set_list_hit_area(
        Rect {
            x: area.x.saturating_add(1),
            y: area.y.saturating_add(1),
            width: area.width.saturating_sub(2),
            height: area.height.saturating_sub(2),
        },
        0,
    );
}

fn render_list(
    frame: &mut Frame<'_>,
    area: Rect,
    title: &str,
    rows: Vec<ListItem<'static>>,
    selected: Option<usize>,
) {
    let empty = rows.is_empty();
    let items = if empty {
        vec![ListItem::new(Line::styled(
            "No items yet. The service may still be initializing.",
            Style::default().fg(Color::DarkGray),
        ))]
    } else {
        rows
    };
    let list = List::new(items)
        .block(Block::default().title(title).borders(Borders::ALL))
        .highlight_symbol("▸ ")
        .highlight_style(
            Style::default()
                .bg(SELECTED_BG)
                .add_modifier(Modifier::BOLD),
        );
    let mut state = ListState::default();
    state.select(if empty { None } else { selected });
    frame.render_stateful_widget(list, area, &mut state);
}

fn wifi_row(network: &WifiNetwork) -> ListItem<'static> {
    let (status, status_style) = connection_label(network.state);
    let present = if network.present {
        ""
    } else {
        "  out of range"
    };
    let saved = if network.saved { "  known" } else { "" };
    ListItem::new(Line::from(vec![
        Span::styled(format!("{status:<14}"), status_style),
        Span::styled(
            network.display_name.clone(),
            Style::default().add_modifier(Modifier::BOLD),
        ),
        Span::styled(
            format!("  {:>3}%", network.signal),
            signal_style(network.signal),
        ),
        Span::styled(saved, Style::default().fg(Color::Blue)),
        Span::styled(present, Style::default().fg(Color::DarkGray)),
    ]))
}

fn bluetooth_row(device: &BluetoothDevice) -> ListItem<'static> {
    let (status, status_style) = connection_label(device.state);
    let paired = if device.paired { "  paired" } else { "" };
    let present = if device.present { "" } else { "  out of range" };
    ListItem::new(Line::from(vec![
        Span::styled(format!("{status:<14}"), status_style),
        Span::styled(
            device.name.clone(),
            Style::default().add_modifier(Modifier::BOLD),
        ),
        Span::styled(
            format!("  {}", device.id.address.0),
            Style::default().fg(Color::DarkGray),
        ),
        Span::styled(paired, Style::default().fg(Color::Blue)),
        Span::styled(present, Style::default().fg(Color::DarkGray)),
    ]))
}

fn connection_label(state: ConnectionState) -> (&'static str, Style) {
    match state {
        ConnectionState::Connected => ("connected", Style::default().fg(Color::Green)),
        ConnectionState::Associating => ("associating", Style::default().fg(Color::Yellow)),
        ConnectionState::Authenticating => ("authenticating", Style::default().fg(Color::Yellow)),
        ConnectionState::ObtainingAddress => ("getting IP", Style::default().fg(Color::Yellow)),
        ConnectionState::Disconnecting => ("disconnecting", Style::default().fg(Color::Yellow)),
        ConnectionState::Failed => ("failed", Style::default().fg(Color::Red)),
        ConnectionState::Disconnected => ("", Style::default().fg(Color::DarkGray)),
    }
}

fn signal_style(signal: u8) -> Style {
    Style::default().fg(match signal {
        70..=u8::MAX => Color::Green,
        40..=69 => Color::Yellow,
        _ => Color::Red,
    })
}

fn draw_details(frame: &mut Frame<'_>, area: Rect, app: &Application) {
    let lines = match app.pane {
        Pane::Wifi => app
            .reducer
            .state
            .wifi
            .selected
            .as_ref()
            .and_then(|id| app.reducer.state.wifi.networks.get(id))
            .map(|network| {
                vec![
                    Line::from(network.display_name.clone()),
                    Line::from(format!("State: {:?}", network.state)),
                    Line::from(format!(
                        "Connectivity: {}",
                        connectivity_label(network.connectivity)
                    )),
                    Line::from(format!("Signal: {}%", network.signal)),
                    Line::from(format!("Security: {:?}", network.id.security)),
                    Line::from(format!("BSS count: {}", network.bss_count)),
                    Line::from(format!("Auto-join: {}", yes_no(network.auto_join))),
                ]
            }),
        Pane::Bluetooth => app
            .reducer
            .state
            .bluetooth
            .selected
            .as_ref()
            .and_then(|id| app.reducer.state.bluetooth.devices.get(id))
            .map(|device| {
                vec![
                    Line::from(device.name.clone()),
                    Line::from(format!("State: {:?}", device.state)),
                    Line::from(format!("Address: {}", device.id.address.0)),
                    Line::from(format!("Paired: {}", yes_no(device.paired))),
                    Line::from(format!("Trusted: {}", yes_no(device.trusted))),
                    Line::from(format!(
                        "Services ready: {}",
                        yes_no(device.services_resolved)
                    )),
                    Line::from(format!(
                        "Battery: {}",
                        device
                            .battery_percent
                            .map_or_else(|| "unknown".into(), |value| format!("{value}%"))
                    )),
                ]
            }),
    }
    .unwrap_or_else(|| {
        vec![Line::styled(
            "Nothing selected",
            Style::default().fg(Color::DarkGray),
        )]
    });

    frame.render_widget(
        Paragraph::new(lines)
            .block(Block::default().title(" Details ").borders(Borders::ALL))
            .wrap(Wrap { trim: false }),
        area,
    );
}

fn connectivity_label(connectivity: Connectivity) -> &'static str {
    match connectivity {
        Connectivity::Unknown => "unknown",
        Connectivity::None => "none",
        Connectivity::Local => "local only",
        Connectivity::Limited => "limited",
        Connectivity::CaptivePortal => "captive portal",
        Connectivity::Internet => "Internet",
    }
}

fn yes_no(value: bool) -> &'static str {
    if value {
        "yes"
    } else {
        "no"
    }
}

fn draw_notification(frame: &mut Frame<'_>, area: Rect, app: &Application) {
    if let Some(error) = &app.reducer.state.current_error {
        frame.render_widget(
            Paragraph::new(Line::from(vec![
                Span::styled(
                    "Error: ",
                    Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
                ),
                Span::raw(error.summary.clone()),
                Span::styled("  Esc dismisses", Style::default().fg(Color::DarkGray)),
            ]))
            .block(Block::default().borders(Borders::TOP))
            .wrap(Wrap { trim: true }),
            area,
        );
    } else if let Some(activity) = app.reducer.state.activity.back() {
        frame.render_widget(
            Paragraph::new(activity.message.clone()).style(activity_style(activity.level)),
            area,
        );
    }
}

fn activity_style(level: ActivityLevel) -> Style {
    Style::default().fg(match level {
        ActivityLevel::Info => Color::Gray,
        ActivityLevel::Success => Color::Green,
        ActivityLevel::Warning => Color::Yellow,
        ActivityLevel::Error => Color::Red,
    })
}

fn draw_footer(frame: &mut Frame<'_>, area: Rect, app: &Application) {
    let search = if app.search.is_empty() {
        String::new()
    } else {
        format!("  filter: {}", app.search)
    };
    frame.render_widget(
        Paragraph::new(format!(
            "Enter connect/disconnect  s scan  / search  Ctrl-P actions  l activity  ? help  q quit{search}"
        ))
        .style(Style::default().fg(Color::DarkGray)),
        area,
    );
}

fn draw_help(frame: &mut Frame<'_>, area: Rect) {
    let popup = centered_rect(64, 70, area);
    frame.render_widget(Clear, popup);
    frame.render_widget(
        Paragraph::new(vec![
            Line::from("Navigation"),
            Line::from("  ↑/↓ or j/k     move selection"),
            Line::from("  g/G             first/last item"),
            Line::from("  1/2 or Tab      switch radio"),
            Line::from(""),
            Line::from("Actions"),
            Line::from("  Enter           connect or disconnect"),
            Line::from("  s               scan/discover"),
            Line::from("  Ctrl-P          command palette"),
            Line::from("  /               filter visible items"),
            Line::from("  l               activity journal"),
            Line::from("  q / Ctrl-C      quit"),
            Line::from(""),
            Line::styled(
                "Esc, Enter, or q closes this window",
                Style::default().fg(Color::DarkGray),
            ),
        ])
        .block(Block::default().title(" Help ").borders(Borders::ALL))
        .wrap(Wrap { trim: false }),
        popup,
    );
}

fn draw_activity(frame: &mut Frame<'_>, area: Rect, app: &Application) {
    let popup = centered_rect(80, 80, area);
    frame.render_widget(Clear, popup);
    let available = usize::from(popup.height.saturating_sub(2));
    let skip = app.reducer.state.activity.len().saturating_sub(available);
    let lines = app
        .reducer
        .state
        .activity
        .iter()
        .skip(skip)
        .map(|entry| {
            Line::styled(
                format!("{:>8}ms  {}", entry.timestamp_ms, entry.message),
                activity_style(entry.level),
            )
        })
        .collect::<Vec<_>>();
    frame.render_widget(
        Paragraph::new(lines)
            .block(Block::default().title(" Activity ").borders(Borders::ALL))
            .wrap(Wrap { trim: false }),
        popup,
    );
}

fn draw_palette(frame: &mut Frame<'_>, area: Rect, app: &Application) {
    let popup = centered_rect(70, 60, area);
    frame.render_widget(Clear, popup);
    let inner = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(1)])
        .split(popup);
    frame.render_widget(
        Paragraph::new(format!("> {}", app.palette_query)).block(
            Block::default()
                .title(" Command palette ")
                .borders(Borders::ALL),
        ),
        inner[0],
    );
    let actions = app.filtered_palette_actions();
    let items = actions
        .iter()
        .map(|action| ListItem::new(action.label()))
        .collect::<Vec<_>>();
    let mut state = ListState::default();
    if !items.is_empty() {
        state.select(Some(app.palette_selected.min(items.len() - 1)));
    }
    frame.render_stateful_widget(
        List::new(items)
            .block(Block::default().borders(Borders::LEFT | Borders::RIGHT | Borders::BOTTOM))
            .highlight_symbol("▸ ")
            .highlight_style(
                Style::default()
                    .bg(SELECTED_BG)
                    .add_modifier(Modifier::BOLD),
            ),
        inner[1],
        &mut state,
    );
}

fn draw_search(frame: &mut Frame<'_>, area: Rect, app: &Application) {
    let popup = centered_rect(60, 15, area);
    frame.render_widget(Clear, popup);
    frame.render_widget(
        Paragraph::new(format!("/{}", app.search))
            .block(Block::default().title(" Filter ").borders(Borders::ALL))
            .alignment(Alignment::Left),
        popup,
    );
}

fn centered_rect(width_percent: u16, height_percent: u16, area: Rect) -> Rect {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - height_percent) / 2),
            Constraint::Percentage(height_percent),
            Constraint::Percentage((100 - height_percent) / 2),
        ])
        .split(area);
    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - width_percent) / 2),
            Constraint::Percentage(width_percent),
            Constraint::Percentage((100 - width_percent) / 2),
        ])
        .split(vertical[1])[1]
}

#[cfg(test)]
mod tests {
    use ratatui::{backend::TestBackend, Terminal};

    use super::*;
    use crate::app::Application;

    fn render(width: u16, height: u16, app: &mut Application) -> String {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal.draw(|frame| draw(frame, app)).unwrap();
        let buffer = terminal.backend().buffer();
        let mut output = String::new();
        for y in 0..height {
            for x in 0..width {
                output.push_str(buffer.get(x, y).symbol());
            }
            output.push('\n');
        }
        output
    }

    #[test]
    fn empty_state_explains_initialization() {
        let screen = render(100, 24, &mut Application::new());
        assert!(screen.contains("probing services"));
        assert!(screen.contains("No items yet"));
        assert!(screen.contains("Ctrl-P actions"));
    }

    #[test]
    fn minimal_terminal_does_not_panic() {
        let screen = render(20, 6, &mut Application::new());
        assert!(!screen.is_empty());
    }

    #[test]
    fn help_and_activity_overlays_render() {
        let mut app = Application::new();
        app.overlay = Some(Overlay::Help);
        assert!(render(100, 30, &mut app).contains("connect or disconnect"));
        app.overlay = Some(Overlay::Activity);
        assert!(render(100, 30, &mut app).contains("radioctl started"));
    }

    #[test]
    fn palette_renders_filtered_actions() {
        let mut app = Application::new();
        app.overlay = Some(Overlay::Palette);
        app.palette_query = "diagnostics".into();
        let screen = render(100, 30, &mut app);
        assert!(screen.contains("Open diagnostics"));
        assert!(!screen.contains("Toggle Wi-Fi radio"));
    }
}
