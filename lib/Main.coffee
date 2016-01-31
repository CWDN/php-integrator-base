module.exports =
    ###*
     * Configuration settings.
    ###
    config:
        phpCommand:
            title       : 'PHP command'
            description : 'The path to your PHP binary (e.g. /usr/bin/php, php, ...).'
            type        : 'string'
            default     : 'php'
            order       : 1

    ###*
     * The name of the package.
    ###
    packageName: 'php-integrator-base'

    ###*
     * The configuration object.
    ###
    configuration: null

    ###*
     * The proxy object.
    ###
    proxy: null

    ###*
     * The exposed service.
    ###
    service: null

    ###*
     * The status bar manager.
    ###
    statusBarManager: null

    ###*
     * Tests the user's configuration.
     *
     * @return {boolean}
    ###
    testConfig: () ->
        ConfigTester = require './ConfigTester'

        configTester = new ConfigTester(@configuration)

        result = configTester.test()

        if not result
            errorMessage =
                "PHP is not correctly set up and as a result PHP integrator will not work. Please visit the settings
                 screen to correct this error. If you are not specifying an absolute path for PHP or Composer, make
                 sure they are in your PATH."

            atom.notifications.addError('Incorrect setup!', {'detail': errorMessage})

            return false

        return true

    ###*
     * Registers any commands that are available to the user.
    ###
    registerCommands: () ->
        fs = require 'fs'

        atom.commands.add 'atom-workspace', "php-integrator-base:index-project": =>
            return @performIndex()

        atom.commands.add 'atom-workspace', "php-integrator-base:force-index-project": =>
            try
                fs.unlinkSync(@proxy.getIndexDatabasePath())

            catch error
                # If the file doesn't exist, just bail out.

            return @performIndex()

        atom.commands.add 'atom-workspace', "php-integrator-base:configuration": =>
            return unless @testConfig()

            atom.notifications.addSuccess 'Success', {
                'detail' : 'Your PHP integrator configuration is working correctly!'
            }

    ###*
     * Registers listeners for config changes.
    ###
    registerConfigListeners: () ->
        @configuration.onDidChange 'phpCommand', () =>
            @performIndex()

    ###*
     * Indexes a file aynschronously.
     *
     * @param {string|null} fileName The file to index, or null to index the entire project.
     * @param {string|null} source   The source code of the file to index.
    ###
    performIndex: (fileName = null, source = null) ->
        timerName = @packageName + " - Project indexing"

        if not fileName
            console.time(timerName);

        if @statusBarManager and fileName is null
            @statusBarManager.setLabel("Indexing...")
            @statusBarManager.setProgress(null)
            @statusBarManager.show()

        successHandler = () =>
            if @statusBarManager
                @statusBarManager.setLabel("Indexing completed!")
                @statusBarManager.hide()

            if not fileName
                console.timeEnd(timerName);

        failureHandler = () =>
            if @statusBarManager
                @statusBarManager.showMessage("Indexing failed!", "highlight-error")

        progressHandler = (progress) =>
            progress = parseFloat(progress)

            if not isNaN(progress)
                @statusBarManager.setProgress(progress)
                @statusBarManager.setLabel("Indexing... (" + progress.toFixed(2) + " %)")

        if not fileName?
            fileName = atom.project.getDirectories()[0]?.path

        @proxy.setIndexDatabaseName(@getIndexDatabaseName())

        @service.reindex(fileName, source, progressHandler).then(successHandler, failureHandler)

    ###*
     * Retrieves the name of the database file to use.
     *
     * @return {string}
    ###
    getIndexDatabaseName: () ->
        pathStrings = ''

        for i,project of atom.project.getDirectories()
            pathStrings += project.path

        md5 = require 'md5'

        return md5(pathStrings)

    ###*
     * Attaches items to the status bar.
     *
     * @param {mixed} statusBarService
    ###
    attachStatusBarItems: (statusBarService) ->
        if not @statusBarManager
            StatusBarManager = require "./Widgets/StatusBarManager"

            @statusBarManager = new StatusBarManager()
            @statusBarManager.initialize(statusBarService)
            @statusBarManager.setLabel("Indexing...")

    ###*
     * Detaches existing items from the status bar.
    ###
    detachStatusBarItems: () ->
        if @statusBarManager
            @statusBarManager.destroy()
            @statusBarManager = null

    ###*
     * Activates the package.
    ###
    activate: ->
        Service       = require './Service'
        AtomConfig    = require './AtomConfig'
        CachingProxy  = require './CachingProxy'
        CachingParser = require './CachingParser'
        {Emitter}     = require 'event-kit';

        @configuration = new AtomConfig(@packageName)

        # See also atom-autocomplete-php pull request #197 - Disabled for now because it does not allow the user to
        # reactivate or try again.
        # return unless @testConfig()
        @testConfig()

        @proxy = new CachingProxy(@configuration)

        emitter = new Emitter()
        parser = new CachingParser(@proxy)

        @service = new Service(@proxy, parser, emitter)

        @registerCommands()
        @registerConfigListeners()

        # In rare cases, the package is loaded faster than the project gets a chance to load. At that point, no project
        # directory is returned. The onDidChangePaths listener below will also catch that case.
        if atom.project.getDirectories().length > 0
            @performIndex()

        atom.project.onDidChangePaths (projectPaths) =>
            # NOTE: This listener is also invoked at shutdown with an empty array as argument, this makes sure we don't
            # try to reindex then.
            if projectPaths.length > 0
                @performIndex()

        atom.workspace.observeTextEditors (editor) =>
            editor.onDidStopChanging () =>
                return unless /text.html.php$/.test(editor.getGrammar().scopeName)

                path = editor.getPath()
                isContainedInProject = false

                for projectDirectory in atom.project.getDirectories()
                    if path.indexOf(projectDirectory.path) != -1
                        isContainedInProject = true
                        break

                # Do not try to index files outside the project.
                if isContainedInProject
                    parser.clearCache(path)
                    @performIndex(path, editor.getBuffer().getText())

    ###*
     * Deactivates the package.
    ###
    deactivate: ->

    ###*
     * Sets the status bar service, which is consumed by this package.
    ###
    setStatusBarService: (service) ->
        @attachStatusBarItems(service)

        # This method is usually invoked after the indexing has already started, hence we can't unconditionally hide it
        # here or it will never be made visible again. However, we also don't want it to be visible for new Atom windows
        # that don't contain a project.
        if atom.project.getDirectories().length == 0
            @statusBarManager.hide()

        {Disposable} = require 'atom'

        return new Disposable => @detachStatusBarItems()

    ###*
     * Retrieves the service exposed by this package.
    ###
    getService: ->
        return @service
