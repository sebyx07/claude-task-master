# frozen_string_literal: true

require "webmock/rspec"

# Shared context for mocking GitHub API calls via Octokit
RSpec.shared_context "with mocked github api", :github_api do
  before do
    # Enable WebMock
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.reset!
  end

  # Helper to stub a GitHub API endpoint
  def stub_github_api(method, path, response_body, status: 200)
    stub_request(method, "https://api.github.com#{path}")
      .to_return(
        status: status,
        body: response_body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  # Helper to load a fixture file
  def load_fixture(name)
    fixture_path = File.join(__dir__, "..", "fixtures", "github_api", "#{name}.json")
    JSON.parse(File.read(fixture_path))
  end

  # Common stubs for GitHub operations
  def stub_github_user(login: "testuser")
    stub_github_api(:get, "/user", { login: login })
  end

  def stub_github_pr(number:, state: "open", mergeable: true)
    stub_github_api(:get, "/repos/owner/repo/pulls/#{number}", {
                      number: number,
                      state: state,
                      mergeable: mergeable,
                      html_url: "https://github.com/owner/repo/pull/#{number}"
                    })
  end

  def stub_github_pr_comments(pr_number:, comments: [])
    stub_github_api(:get, "/repos/owner/repo/issues/#{pr_number}/comments", comments)
  end

  def stub_github_pr_reviews(pr_number:, reviews: [])
    stub_github_api(:get, "/repos/owner/repo/pulls/#{pr_number}/reviews", reviews)
  end
end
