require 'sinatra/base'
require 'json'
require 'octokit'

TITLE_REGEX = Regexp.new('\A\[(bugfix|feature|critical|(new )?locale|misc|tests|pkg)\] ')
GENERATED_FILES_REGEX = Regexp.new('\A((min|locale|build)\/|moment\.js\Z)')
class CITutorial < Sinatra::Base

  # !!! DO NOT EVER USE HARD-CODED VALUES IN A REAL APP !!!
  # Instead, set and test environment variables, like below
  ACCESS_TOKEN = ENV['MY_PERSONAL_GITHUB_TOKEN']
  before do
    @client ||= Octokit::Client.new(:access_token => ACCESS_TOKEN)
  end

  get '/' do
    "moment-bot: source at https://github.com/ichernev/moment-bot"
  end

  post '/event_handler' do
    @payload = JSON.parse(params[:payload])

    case request.env['HTTP_X_GITHUB_EVENT']
    when "pull_request" # trying to capture all PR events
      process_pull_request(@payload["pull_request"])
    end
  end

  helpers do
    def process_pull_request(pull_request)
      puts "Processing pull request \##{pull_request['number']}: #{pull_request['title']}..."
      check_pr_title(pull_request)
      check_no_prs_to_master(pull_request)
      check_no_genfiles_edits(pull_request)
      puts "Pull request \##{pull_request['number']} processed!"
    end

    def check_no_genfiles_edits(pull_request)
      @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'pending', options={:context => "Generated files", :description => "Checking generated files..."})
      errors = false
      # Note: The response includes a maximum of 300 files.
      changed_files      = @client.pull_files(pull_request['base']['repo']['full_name'], pull_request['number'], {:per_page => 100, :page => 1}).map{|x| x[:filename]}
      changed_files.concat(@client.pull_files(pull_request['base']['repo']['full_name'], pull_request['number'], {:per_page => 100, :page => 2}).map{|x| x[:filename]})
      changed_files.concat(@client.pull_files(pull_request['base']['repo']['full_name'], pull_request['number'], {:per_page => 100, :page => 3}).map{|x| x[:filename]})
      for file in changed_files
        if GENERATED_FILES_REGEX.match(file)
          errors = true
          break
        end
      end
      if errors
        @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'error', options={:context => "Generated files", :description => "Don't edit moment.js, min/*, locale/*, build/*."})
      else
        @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'success', options={:context => "Generated files", :description => "No edits to generated files! :)"})
      end
      return "Finished"
    end

    def check_no_prs_to_master(pull_request)
      @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'pending', options={:context => "Base branch", :description => "Checking base branch..."})
      puts "PR is against #{pull_request['base']['ref']}"
      if 'master' == pull_request['base']['ref']
        @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'error', options={:context => "Base branch", :description => "Change the base branch from 'master' to 'develop'."})
      else
        @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'success', options={:context => "Base branch", :description => "Looks good!"})
      end
      return "Finished"
    end

    def check_pr_title(pull_request)
      @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'pending', options={:context => "Title", :description => "Reading title..."})
      if TITLE_REGEX.match(pull_request['title'])
        puts "PR \##{pull_request['number']}'s title looks good: #{pull_request['title']}"
        @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'success', options={:context => "Title", :description => "Your title looks great!"})
      else
        puts "PR \##{pull_request['number']}'s title doesn't pass: #{pull_request['title']}"
        @client.create_status(pull_request['base']['repo']['full_name'], pull_request['head']['sha'], 'error', options={:context => "Title", :description => "Start with [bugfix/feature/critical/new locale/locale/misc/tests/pkg]."})
      end
      return "Finished"
    end
  end
end
