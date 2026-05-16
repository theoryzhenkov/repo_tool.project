use std::io;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crossterm::event::{self, Event, KeyCode, KeyModifiers};
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

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct Run {
    id: String,
    status: String,
    returncode: String,
    requester: String,
    summary: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Focus {
    Requests,
    Grants,
    Runs,
    Detail,
}

struct App {
    requests: Vec<Request>,
    grants: Vec<Grant>,
    runs: Vec<Run>,
    request_state: ListState,
    grant_state: ListState,
    run_state: ListState,
    focus: Focus,
    selected_detail: String,
    status: String,
    last_poll: Instant,
    detail_scroll: u16,
}

impl App {
    fn new() -> Self {
        let mut app = Self {
            requests: Vec::new(),
            grants: Vec::new(),
            runs: Vec::new(),
            request_state: ListState::default(),
            grant_state: ListState::default(),
            run_state: ListState::default(),
            focus: Focus::Requests,
            selected_detail: String::new(),
            status: "starting".to_string(),
            last_poll: Instant::now() - Duration::from_secs(60),
            detail_scroll: 0,
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

    fn selected_run_id(&self) -> Option<String> {
        self.run_state
            .selected()
            .and_then(|idx| self.runs.get(idx))
            .map(|run| run.id.clone())
    }

    fn normalize_selection(state: &mut ListState, len: usize) {
        if len == 0 {
            state.select(None);
            return;
        }
        let selected = state.selected().unwrap_or(0).min(len - 1);
        state.select(Some(selected));
    }

    fn restore_selection<T, F>(state: &mut ListState, items: &[T], previous: Option<String>, id: F)
    where
        F: Fn(&T) -> &str,
    {
        if let Some(previous_id) = previous {
            if let Some(idx) = items.iter().position(|item| id(item) == previous_id) {
                state.select(Some(idx));
                return;
            }
        }
        Self::normalize_selection(state, items.len());
    }

    fn poll(&mut self) {
        let previous_request = self.selected_request_id();
        let previous_grant = self.selected_grant_id();
        let previous_run = self.selected_run_id();

        let requests_text = run_project(&["requests"]).unwrap_or_else(|e| format!("error: {e}"));
        let grants_text = run_project(&["grants"]).unwrap_or_else(|e| format!("error: {e}"));
        let runs_text = run_project(&["runs"]).unwrap_or_else(|e| format!("error: {e}"));

        self.requests = parse_requests(&requests_text);
        self.grants = parse_grants(&grants_text);
        self.runs = parse_runs(&runs_text);

        Self::restore_selection(&mut self.request_state, &self.requests, previous_request, |req| &req.id);
        Self::restore_selection(&mut self.grant_state, &self.grants, previous_grant, |grant| &grant.id);
        Self::restore_selection(&mut self.run_state, &self.runs, previous_run, |run| &run.id);

        self.refresh_detail_preserving_scroll();
        if requests_text.starts_with("error:") || grants_text.starts_with("error:") || runs_text.starts_with("error:") {
            self.status = format!(
                "requests: {} grants: {} runs: {}",
                requests_text.trim(),
                grants_text.trim(),
                runs_text.trim()
            );
        } else if self.status == "starting" || self.status == "ready" {
            self.status = "ready".to_string();
        }
        self.last_poll = Instant::now();
    }

    fn refresh_detail(&mut self) {
        self.detail_scroll = 0;
        self.refresh_detail_preserving_scroll();
    }

    fn refresh_detail_preserving_scroll(&mut self) {
        self.selected_detail = match self.focus {
            Focus::Requests | Focus::Detail => match self.selected_request_id() {
                Some(id) => run_project(&["show", &id]).unwrap_or_else(|e| format!("error: {e}")),
                None => "No pending request selected.".to_string(),
            },
            Focus::Grants => match self.selected_grant_id() {
                Some(id) => format!("Grant {id}\n\nPress v to revoke."),
                None => "No active grant selected.".to_string(),
            },
            Focus::Runs => match self.selected_run_id() {
                Some(id) => run_project(&["logs", &id]).unwrap_or_else(|e| format!("error: {e}")),
                None => "No command run selected.".to_string(),
            },
        };
    }

    fn cycle_focus(&mut self) {
        self.focus = match self.focus {
            Focus::Requests => Focus::Grants,
            Focus::Grants => Focus::Runs,
            Focus::Runs => Focus::Detail,
            Focus::Detail => Focus::Requests,
        };
        self.refresh_detail();
    }

    fn select_next(&mut self) {
        match self.focus {
            Focus::Requests | Focus::Detail => {
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
                    self.refresh_detail();
                }
            }
            Focus::Runs => {
                let len = self.runs.len();
                if len > 0 {
                    let idx = self.run_state.selected().unwrap_or(0);
                    self.run_state.select(Some((idx + 1).min(len - 1)));
                    self.refresh_detail();
                }
            }
        }
    }

    fn select_previous(&mut self) {
        match self.focus {
            Focus::Requests | Focus::Detail => {
                let idx = self.request_state.selected().unwrap_or(0).saturating_sub(1);
                self.request_state.select(Some(idx));
            }
            Focus::Grants => {
                let idx = self.grant_state.selected().unwrap_or(0).saturating_sub(1);
                self.grant_state.select(Some(idx));
            }
            Focus::Runs => {
                let idx = self.run_state.selected().unwrap_or(0).saturating_sub(1);
                self.run_state.select(Some(idx));
            }
        }
        self.refresh_detail();
    }

    fn scroll_detail_down(&mut self) {
        self.detail_scroll = self.detail_scroll.saturating_add(1);
    }

    fn scroll_detail_up(&mut self) {
        self.detail_scroll = self.detail_scroll.saturating_sub(1);
    }

    fn approve(&mut self) {
        if let Some(id) = self.selected_request_id() {
            self.status = first_line(
                &run_project(&["grant", "approve", &id, "--yes", "--background"])
                    .unwrap_or_else(|e| format!("error: {e}")),
            );
            self.focus = Focus::Runs;
            self.poll();
            if let Some(idx) = self.runs.iter().position(|run| run.id == id) {
                self.run_state.select(Some(idx));
                self.refresh_detail();
            }
        }
    }

    fn reject(&mut self) {
        if let Some(id) = self.selected_request_id() {
            self.status = first_line(&run_project(&["grant", "reject", &id]).unwrap_or_else(|e| format!("error: {e}")));
            self.poll();
        }
    }

    fn revoke(&mut self) {
        if let Some(id) = self.selected_grant_id() {
            self.status = first_line(&run_project(&["grant", "revoke", &id]).unwrap_or_else(|e| format!("error: {e}")));
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

fn parse_runs(text: &str) -> Vec<Run> {
    text.lines()
        .filter(|line| !line.starts_with("error:"))
        .filter_map(|line| {
            let mut parts = line.splitn(5, '\t');
            let id = parts.next()?.to_string();
            if !is_request_id(&id) {
                return None;
            }
            Some(Run {
                id,
                status: parts.next().unwrap_or("").to_string(),
                returncode: parts.next().unwrap_or("").to_string(),
                requester: parts.next().unwrap_or("").to_string(),
                summary: compact_text(parts.next().unwrap_or(""), 160),
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
                    KeyCode::Tab => app.cycle_focus(),
                    KeyCode::Char('a') => app.approve(),
                    KeyCode::Char('r') => {
                        if app.focus == Focus::Requests || app.focus == Focus::Detail {
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
                    KeyCode::PageDown => app.scroll_detail_down(),
                    KeyCode::PageUp => app.scroll_detail_up(),
                    KeyCode::Char('d') => app.focus = Focus::Detail,
                    KeyCode::Char('j') if key.modifiers.contains(KeyModifiers::CONTROL) => app.scroll_detail_down(),
                    KeyCode::Char('k') if key.modifiers.contains(KeyModifiers::CONTROL) => app.scroll_detail_up(),
                    _ => {}
                }
            }
        }

        if app.last_poll.elapsed() >= Duration::from_secs(1) {
            app.poll();
        }
    }
}

fn focus_style(active: bool) -> Style {
    if active {
        Style::default().fg(Color::Yellow)
    } else {
        Style::default()
    }
}

fn render(frame: &mut Frame, app: &mut App) {
    let root = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Percentage(30), Constraint::Percentage(45), Constraint::Percentage(25)])
        .split(frame.area());

    let header = Paragraph::new(format!(
        "Project grants  |  q quit  Tab focus  ↑/↓ select  a approve  r reject  v revoke  PgUp/PgDn logs  R refresh\nStatus: {}",
        app.status
    ))
    .block(Block::default().borders(Borders::ALL).title(
        std::env::var("PROJECT_APPROVALS_TUI_TITLE").unwrap_or_else(|_| "Project grants".to_string()),
    ));
    frame.render_widget(header, root[0]);

    let top = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(60), Constraint::Percentage(40)])
        .split(root[1]);

    let request_items: Vec<ListItem> = app
        .requests
        .iter()
        .map(|req| ListItem::new(format!("{}  {}  {}  {}", req.id, req.kind, req.requester, req.summary)))
        .collect();
    let requests = List::new(request_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(focus_style(app.focus == Focus::Requests))
                .title("Pending requests"),
        )
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol("> ");
    frame.render_stateful_widget(requests, top[0], &mut app.request_state);

    let grant_items: Vec<ListItem> = app
        .grants
        .iter()
        .map(|grant| ListItem::new(format!("{}  {} → {}  {}", grant.id, grant.requester, grant.project, grant.remaining)))
        .collect();
    let grants = List::new(grant_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(focus_style(app.focus == Focus::Grants))
                .title("Active grants"),
        )
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol("> ");
    frame.render_stateful_widget(grants, top[1], &mut app.grant_state);

    let detail_title = if app.focus == Focus::Runs {
        "Selected command logs"
    } else {
        "Selected item"
    };
    let detail = Paragraph::new(app.selected_detail.clone())
        .scroll((app.detail_scroll, 0))
        .wrap(Wrap { trim: false })
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(focus_style(app.focus == Focus::Detail || app.focus == Focus::Runs))
                .title(detail_title),
        );
    frame.render_widget(detail, root[2]);

    let run_items: Vec<ListItem> = app
        .runs
        .iter()
        .map(|run| {
            let code = if run.returncode.is_empty() {
                "".to_string()
            } else {
                format!(" ({})", run.returncode)
            };
            ListItem::new(format!("{}  {}{}  {}  {}", run.id, run.status, code, run.requester, run.summary))
        })
        .collect();
    let runs = List::new(run_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(focus_style(app.focus == Focus::Runs))
                .title("Command history (last 100)"),
        )
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol("> ");
    frame.render_stateful_widget(runs, root[3], &mut app.run_state);
}
