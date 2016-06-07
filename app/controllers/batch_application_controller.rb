class BatchApplicationController < ApplicationController
  before_action :lock_under_feature_flag
  before_action :ensure_applicant_is_signed_in, only: :apply

  # GET /apply
  def index
    set_instance_variables
    @batches_open = Batch.open_for_applications
    @batches_ongoing = Batch.applications_ongoing
  end

  # GET /apply/:batch
  def apply
    set_instance_variables
    raise_not_found if current_stage_number.blank?

    case applicant_status
      when :expired
        render "batch_application/stage_#{applicant_stage_number}_expired"
      when :rejected
        render "batch_application/stage_#{applicant_stage_number}_rejection"
      when :submitted
        render "batch_application/stage_#{current_stage_number}_submitted"
      else
        render "batch_application/stage_#{current_stage_number}"
    end
  end

  # POST /apply/:batch
  def submit
    # Only allow applicants who have an ongoing application to submit.
    if applicant_status == :ongoing
      send "submission_for_stage_#{current_stage_number}"
    else
      flash[:error] = 'Something went wrong when attempting to process your submission. Please contact us at help@sv.co.'
      redirect_to apply_batch_path(batch: params[:batch])
    end
  end

  def submission_for_stage_1
    application = BatchApplication.new(
      batch: current_batch,
      application_stage: current_stage,
      team_lead: current_batch_applicant
    )

    # TODO: Something about the application isn't okay.
    raise NotImplementedError unless application.save

    current_batch_applicant.update!(name: params[:batch_application][:team_lead_name])
    application.batch_applicants << current_batch_applicant
    redirect_to apply_batch_path(batch: params[:batch])
  end

  def submission_for_stage_2
    # TODO: Server-side error handling for stage 2 inputs.

    submission = current_application.application_submissions.create!(application_stage: current_stage)

    submission.application_submission_urls.create!(
      name: 'Code Submission',
      url: params[:tests][:github_url]
    )

    submission.application_submission_urls.create!(
      name: 'Video Submission',
      url: params[:tests][:video_url]
    )

    redirect_to apply_batch_path(batch: params[:batch])
  end

  def submission_for_stage_4
    # TODO: Server-side error handling for stage 4 inputs.

    # TODO: How to handle file uploads (if any for pre-selection)?
    current_application.application_submissions.create!(
      application_stage: current_stage
    )

    redirect_to apply_batch_path(batch: params[:batch])
  end

  # GET /apply/identify/:batch
  def identify
    check_token

    if current_batch_applicant.present?
      redirect_to apply_batch_path(batch: params[:batch])
      return
    end

    save_batch(params[:batch])

    @skip_container = true
    @batch_applicant = BatchApplicant.new
  end

  # POST /apply/identify
  def send_sign_in_email
    @skip_container = true
    @batch_applicant = BatchApplicant.find_or_initialize_by email: params[:batch_applicant][:email]

    if @batch_applicant.save
      # Regenerate token.
      @batch_applicant.regenerate_token

      # Send email.
      BatchApplicantMailer.sign_in(@batch_applicant.email, @batch_applicant.token, session[:application_batch]).deliver_later

      render 'batch_application/sign_in_email_sent'
    else
      # There's probably something wrong with the entered email address. Render the form again.
      render 'batch_application/identify'
    end
  end

  protected

  # Returns currently picked batch.
  def current_batch
    @current_batch ||= Batch.find_by(batch_number: params[:batch])
  end

  # Returns the application_stage that current batch is at.
  def current_stage
    @current_stage ||= current_batch&.application_stage
  end

  # Returns the stage number of current batch.
  def current_stage_number
    @current_stage_number ||= current_stage&.number
  end

  # Returns currently 'signed in' application founder.
  def current_batch_applicant
    @current_batch_applicant ||= begin
      return if cookies[:applicant_token].blank?
      BatchApplicant.find_by token: cookies[:applicant_token]
    end
  end

  def applicant_stage
    @applicant_stage ||= begin
      if current_application.blank?
        ApplicationStage.find_by number: 1
      else
        current_application.application_stage
      end
    end
  end

  # Returns stage number of current applicant.
  def applicant_stage_number
    @applicant_stage_number ||= applicant_stage.number
  end

  # Returns batch application of current applicant.
  def current_application
    @current_application ||= current_batch_applicant&.batch_applications.find_by(batch: current_batch)
  end

  helper_method :current_batch
  helper_method :current_batch_applicant
  helper_method :current_stage

  private

  def lock_under_feature_flag
    raise_not_found unless Feature.active?(:application_v2, current_founder)
  end

  def set_instance_variables
    @skip_container = true
    @hide_sign_in = true
  end

  # Returns one of :expired, :rejected, :submitted, or :ongoing, to indicate which view should be rendered.
  #
  # Hari: I'm disabling complexity cops here, because the point of this method is to put the complex state logic in
  # one place. It used to be scattered across many methods, but that became unmanageable, and I had to bring it
  # together to make sense of it all.
  #
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def applicant_status
    if current_application.blank?
      # There's no application...
      if current_stage_number != 1 || stage_expired?
        # ...and the either the batch's stage has moved on, or its deadline has passed.
        :expired
      else
        # ...and it's still stage 1, and stage's deadline hasn't passed.
        :ongoing
      end
    elsif applicant_stage_number == current_stage_number
      # There is an application which is on batch's stage...
      if applicant_has_submitted?
        # ...and it has been submitted.
        :submitted
      else
        # ... and if stage's deadline has passed, then it's expired, otherwise ongoing.
        stage_expired? ? :expired : :ongoing
      end
    elsif applicant_stage_number > current_stage_number
      # The application has been selected for the next stage.
      :submitted
    else
      # Application has been left behind. If a submission exists for application's stage, then it was rejected,
      # otherwise it expired when the stage's deadline passed.
      applicant_has_submitted? ? :rejected : :expired
    end
  end

  def applicant_has_submitted?
    return true if applicant_stage_number == 1

    ApplicationSubmission.where(
      batch_application_id: current_application.id,
      application_stage_id: applicant_stage.id
    ).present?
  end

  # Batch's stage should have expired, and current stage should be same as application stage.
  def stage_expired?
    current_batch.stage_expired?
  end

  # Check whether a token parameter has been supplied. Sign in application founder if there's a corresponding entry.
  def check_token
    return if params[:token].blank?
    applicant = BatchApplicant.find_using_token params[:token]

    if applicant.blank?
      flash[:error] = "That token is invalid. It's likely that it has been used already. Please generate a new one-time link using the form on this page."
      return
    end

    # Sign in the current application founder.
    @current_batch_applicant = applicant

    # Store a cookie that'll keep him / her signed in for 2 months.
    cookies[:applicant_token] = { value: applicant.token, expires: 2.months.from_now }
  end

  # Redirect applicant to sign in page is zhe isn't signed in.
  def ensure_applicant_is_signed_in
    return if current_batch_applicant.present?
    redirect_to apply_identify_url(batch: params[:batch])
  end

  # Save the batch being requested in session. We'll add this info to the sign in link.
  def save_batch(batch)
    return if batch.blank?
    session[:application_batch] = batch
  end
end
