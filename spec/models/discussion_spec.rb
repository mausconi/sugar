require 'spec_helper'

describe Discussion do
  let(:discussion)         { create(:discussion) }
  let(:closed_discussion)  { create(:discussion, closed: true) }
  let(:trusted_discussion) { create(:discussion, category: trusted_category) }
  let(:category)           { create(:category) }
  let(:trusted_category)   { create(:trusted_category) }
  let(:user)               { create(:user) }
  let(:trusted_user)       { create(:trusted_user) }
  let(:moderator)          { create(:moderator) }
  let(:user_admin)         { create(:user_admin) }
  let(:admin)              { create(:admin) }

  it { should have_many(:discussion_relationships).dependent(:destroy) }
  it { should belong_to(:category) }
  it { should validate_presence_of(:category_id) }
  it { should be_kind_of(Exchange) }

  context "in a trusted category" do
    subject { create(:discussion, category: trusted_category) }
    its(:trusted?) { should be_true }
  end

  context "in a regular category" do
    subject { create(:discussion, category: category) }
    its(:trusted?) { should be_false }
  end

  describe 'save callbacks' do
    it "changes the trusted status on discussions" do
      create(:post, discussion: discussion)
      discussion.posts.first.trusted?.should == false
      discussion.update_attributes(category: trusted_category)
      discussion.posts.first.trusted?.should == true
      discussion.update_attributes(category: category)
      discussion.posts.first.trusted?.should == false
    end
  end

  describe ".count_for" do

    before do
      discussion
      trusted_discussion
    end

    context "when user is nil" do
      subject { Discussion.count_for(nil) }
      it { should == 1 }
    end

    context "when user is trusted" do
      subject { Discussion.count_for(trusted_user) }
      it { should == 2 }
    end

    context "when user isn't trusted" do
      subject { Discussion.count_for(user) }
      it { should == 1 }
    end

  end

  describe ".find_popular" do

    subject { Discussion.find_popular }
    it { should be_kind_of(Pagination::InstanceMethods) }

    context "with options" do

      describe :page do

        before { 2.times { create(:discussion) } }

        context "when not specified" do
          subject { Discussion.find_popular(:limit => 1) }
          its(:page) { should == 1 }
        end

        context "when specified" do
          subject { Discussion.find_popular(:limit => 1, :page => 2) }
          its(:page) { should == 2 }
        end

        context "when out of bounds" do
          subject { Discussion.find_popular(:limit => 1, :page => 3) }
          its(:page) { should == 2 }
        end

      end

      describe :since do

        let(:discussion1) { create(:discussion) }
        let(:discussion2) { create(:discussion) }

        before do
          discussion1.posts.first.update_attributes(created_at: 4.days.ago)
          [13.days.ago, 12.days.ago].each do |t|
            create(:post, discussion: discussion1, created_at: t)
          end
          [2.days.ago].each do |t|
            create(:post, discussion: discussion2, created_at: t)
          end
        end

        context "within the last 3 days" do
          subject { Discussion.find_popular(since: 3.days.ago) }
          it { should == [discussion2] }
        end

        context "within the last 7 days" do

          subject { Discussion.find_popular(since: 7.days.ago) }
          it { should == [discussion2, discussion1] }

          describe "the first result" do
            subject { Discussion.find_popular(since: 7.days.ago).first }
            it { should respond_to(:recent_posts_count) }
            specify { subject.recent_posts_count.to_i.should == 2 }
          end

        end

        context "within the last 14 days" do
          subject { Discussion.find_popular(since: 14.days.ago) }
          it { should == [discussion1, discussion2] }
        end

      end

      describe :limit do

        context "when not specified" do
          its(:per_page) { should == Exchange::DISCUSSIONS_PER_PAGE }
        end

        context "when specified" do
          subject { Discussion.find_popular(limit: 7) }
          its(:per_page) { should == 7 }
        end

      end

      describe :trusted do

        let!(:discussion) { create(:discussion) }
        let!(:trusted_discussion) { create(:trusted_discussion) }

        context "when not specified" do
          it { should include(discussion) }
          it { should_not include(trusted_discussion) }
        end

        context "when true" do
          subject { Discussion.find_popular(trusted: true) }
          it { should include(discussion, trusted_discussion) }
        end

        context "when false" do
          subject { Discussion.find_popular(trusted: false) }
          it { should include(discussion) }
          it { should_not include(trusted_discussion) }
        end

      end

    end

  end

  describe "#viewable_by?" do

    context "when discussion is trusted" do

      context "with a regular user" do
        subject { trusted_discussion.viewable_by?(user) }
        it { should be_false }
      end

      context "with a trusted user" do
        subject { trusted_discussion.viewable_by?(trusted_user) }
        it { should be_true }
      end

    end

    context "when discussion isn't trusted" do

      context "when public browsing is on" do
        before { Sugar.config(:public_browsing, true) }
        specify { discussion.viewable_by?(nil).should be_true }
      end

      context "when public browsing is off" do
        before { Sugar.config(:public_browsing, false) }
        specify { discussion.viewable_by?(nil).should be_false }
        specify { discussion.viewable_by?(user).should be_true }
      end

    end

  end

  describe "#editable_by?" do
    specify { discussion.editable_by?(discussion.poster).should be_true }
    specify { discussion.editable_by?(user).should be_false }
    specify { discussion.editable_by?(moderator).should be_true }
    specify { discussion.editable_by?(admin).should be_true }
    specify { discussion.editable_by?(user_admin).should be_false }
    specify { discussion.editable_by?(nil).should be_false }
  end

  describe "#postable_by?" do

    context "when not closed" do
      specify { discussion.postable_by?(user).should be_true }
      specify { discussion.postable_by?(nil).should be_false }
    end

    context "when closed" do
      specify { closed_discussion.postable_by?(user).should be_false }
      specify { closed_discussion.postable_by?(closed_discussion.poster).should be_false }
      specify { closed_discussion.postable_by?(moderator).should be_true }
      specify { closed_discussion.postable_by?(admin).should be_true }
    end

  end

  describe "#closeable_by?" do

    specify { discussion.closeable_by?(user).should be_false }

    context "when not closed" do
      specify { discussion.closeable_by?(discussion.poster).should be_true }
      specify { discussion.closeable_by?(moderator).should be_true }
    end

    context "when closed by the poster" do
      subject { discussion }
      before { discussion.update_attributes(closed: true, updated_by: discussion.poster) }
      specify { discussion.closeable_by?(discussion.poster).should be_true }
      specify { discussion.closeable_by?(moderator).should be_true }
      its(:closer) { should == discussion.poster }
    end

    context "closed by moderator" do
      subject { discussion }
      before { discussion.update_attributes(closed: true, updated_by: moderator) }
      specify { discussion.closeable_by?(discussion.poster).should be_false }
      specify { discussion.closeable_by?(moderator).should be_true }
      its(:closer) { should == moderator }
    end

  end

end
