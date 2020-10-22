# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'erb'
require 'json'

require "#{File.dirname(__FILE__)}/resources/os_lib_reporting"
require "#{File.dirname(__FILE__)}/resources/os_lib_helper_methods"

# start the measure
class OccupantCentricKPIReport < OpenStudio::Measure::ReportingMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Occupant-centric KPI report'
  end

  # human readable description
  def description
    return 'This measure calculate the Occupant-centric Key Performance Indicators (KPIs) and reports them.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'To enable the visual KPIs calculation, please make sure there are daylighting sensors objects in the space(s). To enable the thermal KPIs calculation, please make sure the thermal comfort model type is defined for the OS:People:Definition object. To enable air quality KPIs calculation, please make sure there are ZoneAirContaminationBalance object in the model and an associated outdoor air CO2 concentration schedule.'
  end


  def possible_sections
    result = []

    # methods for sections in order that they will appear in report
    ############################################################################
    result << 'overall_kpi_section'
    # result << 'visual_kpi_section'
    # result << 'thermal_kpi_section'
    # result << 'air_quality_kpi_section'
    # result << 'other_kpi_section'

    result
  end

  # define the arguments that the user will input
  def arguments
    puts '---> In Measure.arguments now...'
    args = OpenStudio::Measure::OSArgumentVector.new

    # chs = OpenStudio::StringVector.new
    # chs << 'IP'
    # chs << 'SI'
    # units = OpenStudio::Measure::OSArgument.makeChoiceArgument('units', chs, true)
    # units.setDisplayName('Which Unit System do you want to use?')
    # units.setDefaultValue('IP')
    # args << units

    # populate arguments
    possible_sections.each do |method_name|

      # display_name = eval("OsLib_Reporting.#{method_name}(nil,nil,nil,true,nil,nil)[:title]")

      begin
        # get display name
        arg = OpenStudio::Measure::OSArgument.makeBoolArgument(method_name, true)
        display_name = eval("OsLib_Reporting.#{method_name}(nil,nil,nil,true,nil)[:title]")
        arg.setDescription("Choose whether or not to report #{method_name}")
        arg.setDisplayName(display_name)
        arg.setDefaultValue(true)
        args << arg
        # if display_name == 'Air Quality KPIs'
        #   # Add air quality KPI related arguments
        #   # arg = OpenStudio::Measure::OSArgument.makeBoolArgument('enable_outdoor_co2', true)
        #   arg = OpenStudio::Measure::OSArgument.makeDoubleArgument('outdoor_co2_level', true)
        #   arg.setDescription("This value will be used if 'Air Quality KPIs' is checked.")
        #   arg.setDisplayName('Outdoor CO2 concentration')
        #   arg.setDefaultValue(400)
        #   args << arg
        # end
      rescue
        next
      end
    end

    args
  end

  # define the outputs that the measure will create
  def outputs
    outs = OpenStudio::Measure::OSOutputVector.new

    # this measure does not produce machine readable outputs with registerValue, return an empty list

    return outs
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  # Warning: Do not change the name of this method to be snake_case. The method must be lowerCamelCase.
  def energyPlusOutputRequests(runner, user_arguments)
    puts '---> In energyPlusOutputRequests now...'
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new
    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return result
    end
    # Add output variables needed from EnergyPlus
    result << OpenStudio::IdfObject.load('Output:Variable,,Site Outdoor Air Drybulb Temperature,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone People Occupant Count,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Lights Electric Power,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Lights Electric Energy,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Electric Equipment Electric Energy,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Electric Equipment Electric Power,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Air Temperature,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Thermal Comfort Fanger Model PMV,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Thermal Comfort Fanger Model PPD,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Operative Temperature,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Air CO2 Concentration,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Mechanical Ventilation Standard Density Volume,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Zone Mechanical Ventilation Standard Density Volume Flow Rate,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Fan Electric Power,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Facility Total Electric Demand Power,timestep;').get

    result << OpenStudio::IdfObject.load('Output:Variable,*,Daylighting Reference Point 1 Illuminance,timestep;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Daylighting Reference Point 2 Illuminance,timestep;').get
    result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # get sql, model, and web assets
    setup = OsLib_Reporting.setup(runner)
    unless setup
      return false
    end
    model = setup[:model]
    # workspace = setup[:workspace]
    sql_file = setup[:sqlFile]
    web_asset_path = setup[:web_asset_path]

    # assign the user inputs to variables
    args = OsLib_HelperMethods.createRunVariables(runner, model, user_arguments, arguments)
    unless args
      return false
    end

    # reporting final condition
    runner.registerInitialCondition('Gathering data from EnergyPlus SQL file and OSM model.')

    # pass measure display name to erb
    @name = name

    # create a array of sections to loop through in erb file
    @sections = []

    # generate data for requested sections
    sections_made = 0
    possible_sections.each do |method_name|
      next unless args[method_name]
      section = false
      eval("section = OsLib_Reporting.#{method_name}(model,sql_file,runner,false,args,nil)")
      display_name = eval("OsLib_Reporting.#{method_name}(nil,nil,nil,true)[:title]")
      if section
        @sections << section
        sections_made += 1
        # look for emtpy tables and warn if skipped because returned empty
        section[:tables].each do |table|
          if !table
            runner.registerWarning("A table in #{display_name} section returned false and was skipped.")
            section[:messages] = ["One or more tables in #{display_name} section returned false and was skipped."]
          end
        end
      else
        runner.registerWarning("#{display_name} section returned false and was skipped.")
        section = {}
        section[:title] = display_name.to_s
        section[:tables] = []
        section[:messages] = []
        section[:messages] << "#{display_name} section returned false and was skipped."
        @sections << section
      end
      # rescue StandardError => e
      #   display_name = eval("OsLib_Reporting.#{method_name}(nil,nil,nil,true)[:title]")
      #   if display_name.nil? then display_name == method_name end
      #   runner.registerWarning("#{display_name} section failed and was skipped because: #{e}. Detail on error follows.")
      #   runner.registerWarning(e.backtrace.join("\n").to_s)

      #   # add in section heading with message if section fails
      #   section = eval("OsLib_Reporting.#{method_name}(nil,nil,nil,true)")
      #   section[:title] = display_name.to_s
      #   section[:tables] = []
      #   section[:messages] = []
      #   section[:messages] << "#{display_name} section failed and was skipped because: #{e}. Detail on error follows."
      #   section[:messages] << [e.backtrace.join("\n").to_s]
      #   @sections << section
    end

    # read in template
    html_in_path = "#{File.dirname(__FILE__)}/resources/report.html.erb"
    if File.exist?(html_in_path)
      html_in_path = html_in_path
    else
      html_in_path = "#{File.dirname(__FILE__)}/report.html.erb"
    end
    html_in = ''
    File.open(html_in_path, 'r') do |file|
      html_in = file.read
    end

    # configure template with variable values
    renderer = ERB.new(html_in)
    html_out = renderer.result(binding)

    # write html file
    html_out_path = './report.html'
    File.open(html_out_path, 'w') do |file|
      file << html_out
      # make sure data is written to the disk one way or the other
      begin
        file.fsync
      rescue StandardError
        file.flush
      end
    end

    # closing the sql file
    sql_file.close

    # reporting final condition
    runner.registerFinalCondition("Generated report with #{sections_made} sections to #{html_out_path}.")

    true
  end
end

# register the measure to be used by the application
OccupantCentricKPIReport.new.registerWithApplication
