use std::io;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crossterm::event::{self, Event, KeyCode};
use crossterm::execute;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::prelude::*;
use ratatui::style::{Color, Modifier, Style};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct Request {
    id: String,
    kind: String,
    requester: String,
    summary: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct Grant {
    id: String,
    requester: String,
    project: String,
    remaining: String,
    workdir: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Focus {
    Requests,
    Grants,
}

struct App {
    requests: Vec<Request>,
    grants: Vec<Grant>,
    request_state: ListState,
    grant_state: ListState,
    focus: Focus,
    selected_detail: String,
    status: String,
    last_poll: Instant,
}

impl App {
    fn new() -> Self {
        let mut app = Self {
            requests: Vec::new(),
            grants: Vec::new(),
            request_state: ListState::default(),
            grant_state: ListState::default(),
            focus: Focus::Requests,
            selected_detail: String::new(),
            status: "starting".to_string(),
            last_poll: Instant::now() - Duration::from_secs(60),
        };
        app.poll();
        app
    }

    fn selected_request_id(&self) -> Option<String> {
        self.request_state
            .selected()
            .and_then(|idx| self.requests.get(idx))
            .map(|req| req.id.clone())
    }

    fn selected_grant_id(&self) -> Option<String> {
        self.grant_state
            .selected()
            .and_then(|idx| self.grants.get(idx))
            .map(|grant| grant.id.clone())
    }

    fn normalize_selection(state: &mut ListState, len: usize) {
        if len == 0 {
            state.select(None);
            return;
        }
        let selected = state.selected().unwrap_or(0).min(len - 1);
        state.select(Some(selected));
    }

    fn poll(&mut self) {
        let previous_request = self.selected_request_id();
        let previous_grant = self.selected_grant_id();

        let requests_text = run_project(&["requests"]).unwrap_or_else(|e| format!("error: {e}"));
        let grants_text = run_project(&["grants"]).unwrap_or_else(|e| format!("error: {e}"));

        self.requests = parse_requests(&requests_text);
        self.grants = parse_grants(&grants_text);

        if let Some(id) = previous_request {
            if let Some(idx) = self.requests.iter().position(|req| req.id == id) {
                self.request_state.select(Some(idx));
            } else {
                Self::normalize_selection(&mut self.request_state, self.requests.len());
            }
        } else {
            Self::normalize_selection(&mut self.request_state, self.requests.len());
        }

        if let Some(id) = previous_grant {
            if let Some(idx) = self.grants.iter().position(|grant| grant.id == id) {
                self.grant_state.select(Some(idx));
            } else {
                Self::normalize_selection(&mut self.grant_state, self.grants.len());
            }
        } else {
            Self::normalize_selection(&mut self.grant_state, self.grants.len());
        }

        self.refresh_detail();
        if requests_text.starts_with("error:") || grants_text.starts_with("error:") {
            self.status = format!("requests: {} grants: {}", requests_text.trim(), grants_text.trim());
        } else if self.status == "starting" || self.status == "ready" {
            self.status = "ready".to_string();
        }
        self.last_poll = Instant::now();
    }

    fn refresh_detail(&mut self) {
        self.selected_detail = match self.selected_request_id() {
            Some(id) => run_project(&["show", &id]).unwrap_or_else(|e| format!("error: {e}")),
            None => "No pending request selected.".to_string(),
        };
    }

    fn select_next(&mut self) {
        match self.focus {
            Focus::Requests => {
                let len = self.requests.len();
                if len > 0 {
                    let idx = self.request_state.selected().unwrap_or(0);
                    self.request_state.select(Some((idx + 1).min(len - 1)));
                    self.refresh_detail();
                }
            }
            Focus::Grants => {
                let len = self.grants.len();
                if len > 0 {
                    let idx = self.grant_state.selected().unwrap_or(0);
                    self.grant_state.select(Some((idx + 1).min(len - 1)));
                }
            }
        }
    }

    fn select_previous(&mut self) {
        match self.focus {
            Focus::Requests => {
                let idx = self.request_state.selected().unwrap_or(0).saturating_sub(1);
                self.request_state.select(Some(idx));
                self.refresh_detail();
            }
            Focus::Grants => {
                let idx = self.grant_state.selected().unwrap_or(0).saturating_sub(1);
                self.grant_state.select(Some(idx));
            }
        }
    }

    fn approve(&mut self) {
        if let Some(id) = self.selected_request_id() {
            self.status = first_line(&run_project(&["approve", &id, "--yes"]).unwrap_or_else(|e| format!("error: {e}")));
            self.poll();
        }
    }

    fn reject(&mut self) {
        if let Some(id) = self.selected_request_id() {
            self.status = first_line(&run_project(&["reject", &id]).unwrap_or_else(|e| format!("error: {e}")));
            self.poll();
        }
    }

    fn revoke(&mut self) {
        if let Some(id) = self.selected_grant_id() {
            self.status = first_line(&run_project(&["revoke", &id]).unwrap_or_else(|e| format!("error: {e}")));
            self.poll();
        }
    }
}

fn run_project(args: &[&str]) -> io::Result<String> {
    let output = Command::new("project")
        .args(args)
        .stdin(Stdio::null())
        .output()?;
    let mut text = String::from_utf8_lossy(&output.stdout).to_string();
    if !output.status.success() {
        text.push_str(&String::from_utf8_lossy(&output.stderr));
    }
    Ok(text)
}

fn first_line(text: &str) -> String {
    text.lines().next().unwrap_or("done").to_string()
}

fn is_request_id(value: &str) -> bool {
    value.len() == 12 && value.chars().all(|ch| ch.is_ascii_hexdigit())
}

fn compact_text(value: &str, max_chars: usize) -> String {
    let text = value.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut chars = text.chars();
    let shortened: String = chars.by_ref().take(max_chars).collect();
    if chars.next().is_some() {
        format!("{shortened}...")
    } else {
        shortened
    }
}

fn parse_requests(text: &str) -> Vec<Request> {
    text.lines()
        .filter(|line| !line.starts_with("error:"))
        .filter_map(|line| {
            let mut parts = line.splitn(4, '\t');
            let id = parts.next()?.to_string();
            if !is_request_id(&id) {
                return None;
            }
            Some(Request {
                id,
                kind: parts.next().unwrap_or("").to_string(),
                requester: parts.next().unwrap_or("").to_string(),
                summary: compact_text(parts.next().unwrap_or(""), 160),
            })
        })
        .collect()
}

fn parse_grants(text: &str) -> Vec<Grant> {
    text.lines()
        .filter(|line| !line.starts_with("error:"))
        .filter_map(|line| {
            let mut parts = line.splitn(5, '\t');
            Some(Grant {
                id: parts.next()?.to_string(),
                requester: parts.next().unwrap_or("").to_string(),
                project: parts.next().unwrap_or("").to_string(),
                remaining: parts.next().unwrap_or("").to_string(),
                workdir: parts.next().unwrap_or("").to_string(),
            })
        })
        .collect()
}

fn main() -> io::Result<()> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let result = run_app(&mut terminal);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}

fn run_app(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> io::Result<()> {
    let mut app = App::new();
    loop {
        terminal.draw(|frame| render(frame, &mut app))?;

        let timeout = Duration::from_millis(250);
        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Tab => {
                        app.focus = if app.focus == Focus::Requests {
                            Focus::Grants
                        } else {
                            Focus::Requests
                        };
                    }
                    KeyCode::Char('a') => app.approve(),
                    KeyCode::Char('r') => {
                        if app.focus == Focus::Requests {
                            app.reject();
                        }
                    }
                    KeyCode::Char('v') => {
                        if app.focus == Focus::Grants {
                            app.revoke();
                        }
                    }
                    KeyCode::Char('R') => app.poll(),
                    KeyCode::Down => app.select_next(),
                    KeyCode::Up => app.select_previous(),
                    _ => {}
                }
            }
        }

        if app.last_poll.elapsed() >= Duration::from_secs(2) {
            app.poll();
        }
    }
}

fn render(frame: &mut Frame, app: &mut App) {
    let root = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Percentage(38),
            Constraint::Percentage(32),
            Constraint::Percentage(30),
        ])
        .split(frame.area());

    let header = Paragraph::new(format!(
        "Project approvals  |  q quit  Tab focus  ↑/↓ select  a approve  r reject  v revoke  R refresh\nStatus: {}",
        app.status
    ))
    .block(Block::default().borders(Borders::ALL).title("Nebula"));
    frame.render_widget(header, root[0]);

    let request_items: Vec<ListItem> = app
        .requests
        .iter()
        .map(|req| ListItem::new(format!("{}  {}  {}  {}", req.id, req.kind, req.requester, req.summary)))
        .collect();
    let request_block = Block::default()
        .borders(Borders::ALL)
        .border_style(if app.focus == Focus::Requests { Style::default().fg(Color::Yellow) } else { Style::default() })
        .title("Pending requests");
    let requests = List::new(request_items)
        .block(request_block)
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol("> ");
    frame.render_stateful_widget(requests, root[1], &mut app.request_state);

    let detail = Paragraph::new(app.selected_detail.clone())
        .wrap(Wrap { trim: false })
        .block(Block::default().borders(Borders::ALL).title("Selected request"));
    frame.render_widget(detail, root[2]);

    let grant_items: Vec<ListItem> = app
        .grants
        .iter()
        .map(|grant| {
            ListItem::new(format!(
                "{}  {} → {}  {}  {}",
                grant.id, grant.requester, grant.project, grant.remaining, grant.workdir
            ))
        })
        .collect();
    let grant_block = Block::default()
        .borders(Borders::ALL)
        .border_style(if app.focus == Focus::Grants { Style::default().fg(Color::Yellow) } else { Style::default() })
        .title("Active grants");
    let grants = List::new(grant_items)
        .block(grant_block)
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol("> ");
    frame.render_stateful_widget(grants, root[3], &mut app.grant_state);
}
