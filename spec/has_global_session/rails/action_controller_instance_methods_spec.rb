require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec_helper'))

class StubRequest
  attr_reader :env, :cookies, :params
  attr_accessor :session

  def initialize(env, cookies, params, local_session={})
    @env     = env
    @cookies = cookies
    @params  = params
    @session = local_session
  end
end

class StubResponse
  def initialize(cookies)
    @cookies = cookies
  end

  def set_cookie(key, hash)
    @cookies[key] = hash[:value]
  end
end

# Stub controller into which we manually wire the GlobalSession instance methods.
# Normally this would be accomplished via the "has_global_session" class method of
# ActionController::Base, but we want to avoid the configuration-related madness.
class StubController < ActionController::Base
  include GlobalSession::Rails::ActionControllerInstanceMethods

  def initialize(env={}, cookies={}, local_session={}, params={})
    super()

    self.request  = StubRequest.new(env, cookies, params)
    self.response = StubResponse.new(cookies)
    @_session = local_session
  end
end

describe GlobalSession::Rails::ActionControllerInstanceMethods do
  include SpecHelper

  before(:all) do
    @keystore = KeyFactory.new
    @keystore.create('authority1', true)
    @keystore.create('authority2', false)
  end

  after(:all) do
    @keystore.destroy
  end

  before(:each) do
    mock_config('common/attributes/signed', ['user'])
    mock_config('common/attributes/insecure', ['favorite_color'])
    mock_config('test/timeout', '60')
    mock_config('test/cookie/name', 'global_session_cookie')
    mock_config('test/cookie/domain', 'localhost')
    mock_config('test/trust', ['authority1'])
    mock_config('test/authority', 'authority1')

    ActionController::Base.global_session_config = mock_config

    @directory        = Directory.new(mock_config, @keystore.dir)
    @original_session = Session.new(@directory)
    @cookie           = @original_session.to_s

    @controller = StubController.new( {'global_session'=>@original_session}, 
                                      {'global_session_cookie'=>@cookie} )
    flexmock(@controller).should_receive(:global_session_create_directory).and_return(@directory)
  end

  after(:each) do
    @keystore.reset
    reset_mock_config
  end

  context :global_session_initialize do
    context 'when no session exists in the Rack env' do
      it 'should initialize a new session'
    end

    context 'when a trusted signature is cached' do
      it 'should not revalidate the signature'      
    end

    context 'when no trusted signature is cached' do
      it 'should revalidate the signature'
    end

    context 'when an exception is raised' do
      it 'should create a new session, update the cookie, and re-raise'
    end
  end

  context :global_session_skip_update do
    it 'should work as expected'
  end

  context :global_session_skip_renew do
    it 'should work as expected'
  end

  context :session_with_global_session do
    context 'when no global session has been instantiated yet' do
      before(:each) do
        @controller.global_session.should be_nil
      end

      it 'should return the Rails session' do
        flexmock(@controller).should_receive(:session_without_global_session).and_return('local session')
        @controller.session.should == 'local session'
      end
    end
    context 'when a global session has been instantiated' do
      before(:each) do
        @controller.global_session_initialize
      end

      it 'should return an integrated session' do
        IntegratedSession.should === @controller.session
      end
    end
    context 'when the global session has been reset' do
      before(:each) do
        @controller.global_session_initialize
        @old_integrated_session = @controller.session
        IntegratedSession.should === @old_integrated_session
        @controller.instance_variable_set(:@global_session, 'new global session')
      end

      it 'should return a fresh integrated session' do
        @controller.session.should_not == @old_integrated_session
      end
    end
    context 'when the local session has been reset' do
      before(:each) do
        @controller.global_session_initialize
        @old_integrated_session = @controller.session
        IntegratedSession.should === @old_integrated_session
        @controller.request.session = 'new local session'
      end

      it 'should return a fresh integrated session' do
        @controller.request.session.should_not == @old_integrated_session
      end
    end
  end
end
