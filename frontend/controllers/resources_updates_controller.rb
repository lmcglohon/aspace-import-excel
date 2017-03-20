class ResourcesUpdatesController < ApplicationController

#  groups of variables

# Identifying the resource: collection_id, ead (if both, they have to match)
# the archival object : ref_id<-- ignored for the moment, Title(R) unit_id hiearchy(R) level(R) publish(t/f) restrictions_flag
  #  processing_note n_abstract n_accessrestrict n_acqinfo n_arrangement n_bioghist n_custodhist n_dimensions n_odd n_langmaterial n_physdesc n_physfacet n_physloc n_prefercite n_processinfo n_relatedmaterial n_scopecontent n_separatedmaterial n_userestrict


# dates: dates_label(default Creation) begin end date_type(R -- bulk,single inclusive) expression certainty

# extents: portion(default whole) number(R) extent_type(R) container_summary physical_details dimensions

# container: type_1 indicator_1 barcode type_2 indicator_2 type_3 indicator_3

# digital object: digital_object_title digital_object_link thumbnail

# Creator agent: creator_1_primary_name creator_1_rest_of_name creator_1_agent_record_id creator_person_1_authority creator_person_1_auth_id creator_1_relator
#   creator_2_primary_name creator_2_rest_of_name creator_2_agent_record_id creator_person_2_authority creator_person_2_auth_id creator_2_relator
#   creator_3_primary_name creator_3_rest_of_name creator_3_agent_record_id creator_person_3_authority creator_person_3_auth_id creator_3_relator
#  family_agent family_agent_record_id family_agent_authority family_agent_authority_id family_agent_relator

# linked_corporate_entity_agent corporate_agent_record_id corporate_agent_authority corporate_agent_authority_id corporate_entity_relator

  # subject: subject_1_term subject_1_type subject_2_term subject_2_type



#       


START_MARKER = /ArchivesSpace field code \(please don't edit this row\)/

  set_access_control "update_resource_record" => [:new, :edit, :create, :update, :rde, :add_children, :publish, :accept_children, :load_ss, :get_file]

  require 'pry'
  require 'rubyXL'
#  include ExportHelper

  def get_file
    rid = params[:rid]
    type = params[:type]
    aoid = params[:aoid] || ''
    ref_id = params[:ref_id] || ''
    resource = params[:resource]
    position = params[:position] || '1'
    return render_aspace_partial :partial => "resources/bulk_file_form",  :locals => {:rid => rid, :aoid => aoid, :type => type, :ref_id => ref_id, :resource => resource, :position => position} 
  end

  # load in a spreadsheet
  def load_ss
    @position
    @parent = Resource.find(params[:rid])
#    Pry::ColorPrinter.pp ['resource', @parent]
    aoid = params[:aoid] 
    @hier = 0
    if !aoid.blank?
      @ao = JSONModel(:archival_object).find(aoid, find_opts )
      @hier = @ao.level
      @hier = @hier.to_i if @ao.level
      @position = @ao.position
      @ao_parent = @ao.parent
      Pry::ColorPrinter.pp ['archival object','position', @position]
      Pry::ColorPrinter.pp ['ref_id', @ao.ref_id, 'level', @ao.level]
      Pry::ColorPrinter.pp ['parent', @ao_parent['ref']] if @ao_parent
    end
    begin
      dispatched_file = params[:file]
      @orig_filename = dispatched_file.original_filename
      @input_file = dispatched_file.tempfile
      Pry::ColorPrinter.pp @input_file
      workbook = RubyXL::Parser.parse(@input_file)
      sheet = workbook[0]
      rows = sheet.enum_for(:each)
      @counter = 0
      Pry::ColorPrinter.pp ["sheet size", sheet.sheet_data.size]
      while @headers.nil? && (row = rows.next)
        @counter += 1
        if row[0] && row[0].value =~ START_MARKER
          @headers = row_values(row)
        # Skip the human readable header too
          rows.next
          @counter += 1 # for the skipping
        end
      end
      raise ExcelImportException.new(I18n.t('plugins.aspace-import-excel.error.no_header')) if @headers.nil?
      @rows_processed = 0
      @report_out = []
      @error_rows = 0
      begin
        while (row = rows.next)
          @counter += 1 
          values = row_values(row)
          if values.compact.empty?
            @counter += 1
            next 
          end
          @row_hash = Hash[@headers.zip(values)]
#          Pry::ColorPrinter.pp @row_hash
          begin
            process_row
            @rows_processed += 1
          rescue ExcelImportException => e
            @error_rows += 1
            @report_out.push e.message
            @report_out.push ' '
            Pry::ColorPrinter.pp e.message
          end
        end
      rescue StopIteration
        begin
        Pry::ColorPrinter.pp ["stop iteration at counter", @counter]
        end
      end
    raise ExcelImportException.new( I18n.t('plugins.aspace-import-excel.error.no_data') + '\n' + @report_out.join('\n')) if @rows_processed == 0
    rescue Exception => e
      errors = []
      if e.is_a?( ExcelImportException)
        errors = e.message.split('\n')
        Pry::ColorPrinter.pp "WE GOT ROW ERRORS!"
        errors.unshift I18n.t('plugins.aspace-import-excel.error.excel', :file => @orig_filename)
      else # something else went wrong
        errors = @report_out
        errors.unshift I18n.t('plugins.aspace-import-excel.error.system',:row => @counter, :msg => e.message)
        Pry::ColorPrinter.pp "EXCEPTION!" 
        Pry::ColorPrinter.pp e.backtrace
      end
      return render_aspace_partial :status => 400,  :partial => "resources/bulk_response", :locals => {:rid => params[:rid],
        :errors =>  errors}
    end
    Pry::ColorPrinter.pp "REPORT OUT"
    Pry::ColorPrinter.pp  @report_out
    return render_aspace_partial :partial => "resources/bulk_response", :locals => {:rid => params[:rid], :report => @report_out}
  end

  private
#    @archival_object =  JSONModel(:archival_object).new
#    @archival_object.resource = {'ref' => JSONModel(:resource).uri_for(params[:rid]) }
#    @archival_object.title = 'Created by load_ss take 4'
#    @archival_object.level = 'item'
#    test_ao = JSONModel(:archival_object).find('84944', {})
#     Pry::ColorPrinter.pp ['arch_obj', @archival_object]
#    Pry::ColorPrinter.pp ['found ao', test_ao]
#    Pry::ColorPrinter.pp ['exception checking:', @archival_object._exceptions]
#    top_container = 'box 144'
#    uri = '/repositories/2/resources/382'
#    repo_id = 2
#    tc_params = {}
#    tc_params["type[]"] = 'top_container'
#    tc_params["q"] = "display_string:\"#{top_container}\" AND collection_uri_u_sstr:\"#{uri}\""
#    tc_params["filter"] = AdvancedQueryBuilder.new.and('collection_uri_u_sstr', uri, 'text', true).build.to_json
#    search = Search.all(repo_id, tc_params)
#    Pry::ColorPrinter.pp ['top_container search', tc_params,search['total_hits'], search['results'][0]['uri']]
#    if search['total_hits'] = 1
#      @archival_object['instances'] = {}
#    end

#    begin
#      @archival_object.save
#      Pry::ColorPrinter.pp @archival_object
#    rescue Exception => e
#      Pry::ColorPrinter.pp ["EXCEPTION", @archival_object._exceptions, e.backtrace]
#    end

  # look for all the required fields to make sure they are legit
  def check_row
    err_arr = []
    begin
      err_arr.push I18n.t('plugins.aspace-import-excel.error.title') if @row_hash['title'].blank?
      # tree hierachy
      hier = @row_hash['hierarchy']
      if !hier 
        err_arr.push I18n.t('plugins.aspace-import-excel.error.hier_miss')
      else
        hier = hier.to_i
        err_arr.push I18n.t('plugins.aspace-import-excel.error.hier_zero') if hier < 1
        err_arr.push I18n.t('plugins.aspace-import-excel.error.hier_wrong') if (hier - 1) > @hier
      end
      err_arr.push I18n.t('plugins.aspace-import-excel.error.level') if @row_hash['level'].blank?
      #date stuff
      err_arr.push I18n.t('plugins.aspace-import-excel.error.date') if [@row_hash['begin'],@row_hash['end'],@row_hash['expression']].compact.empty?
      # extent
      err_arr.push I18n.t('plugins.aspace-import-excel.error.number') if @row_hash['number'].blank?
      err_arr.push I18n.t('plugins.aspace-import-excel.error.extent_type') if @row_hash['extent_type'].blank?
    rescue Exception => e
      Pry::ColorPrinter.pp ["EXCEPTION", e.message, e.backtrace, @row_hash]
    end
      err_arr.join('; ')
  end

  def process_row
    Pry::ColorPrinter.pp @counter
    ret_str =  resource_match
    # mismatch of resource stops all other processing
    if ret_str.blank?
      ret_str = check_row
    end
    raise ExcelImportException.new( I18n.t('plugins.aspace-import-excel.row_error', :row => @counter, :errs => ret_str )) if !ret_str.blank?
    @report_out.push  I18n.t('plugins.aspace-import-excel.row', :row =>@counter)

#    archival_object =  JSONModel(:archival_object).new
  end

  # make sure that the resource ead id from the form matches that in the spreadsheet
  # throws an exception if the designated resource ead doesn't match the spreadsheet row ead
  def resource_match
    ret_str = ''
    ret_str = I18n.t('plugins.aspace-import-excel.error.res_ead') if @parent['ead_id'].blank?
    ret_str =  ' ' +  I18n.t('plugins.aspace-import-excel.error.row_ead')  if @row_hash['ead'].strip.blank?
    if ret_str.blank?
      ret_str =  I18n.t('plugins.aspace-import-excel.error.ead_mismatch', :res_ead => @parent['ead_id'], :row_ead => @row_hash['ead']) if  @parent['ead_id'] != @row_hash['ead'].strip
    end
    ret_str.blank? ? nil : ret_str
  end

  def find_subject(subject,source, ext_id)
    #title:subject AND primary_type:subject AND source:#{source} AND external_id:#{ext_id}
  end

  def find_agent(primary_name, rest_name, type, source, ext_id)
    #title: #{primary_name}, #{rest_name} AND primary_type:agent_#{type}  AND source:#{source} AND external_id:#{ext_id}
  end

  def add_children
   #http://welling.hul.harvard.edu:8880/archival_objects/84957/accept_children
    # children[] = /repositories/2/archival_objects/84958
    #children[] = /repositories/2/archival_objects/84959
    # index = 0
    # this calls handle_accept_children in application_controller https://github.com/archivesspace/archivesspace/blob/c80d9b2205aa36474fe719f3599f83dad8e97bb4/frontend/app/controllers/application_controller.rb
    # 
  end

  def row_values(row)
#    Pry::ColorPrinter.pp "ROW!"
    (1...row.size).map {|i| (row[i] && row[i].value) ? row[i].value.to_s.strip : nil}
  end
end