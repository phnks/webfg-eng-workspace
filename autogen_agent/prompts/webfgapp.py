def WEBFG_APP_PROMPT ():   
  webfg_app_prompt =  f"""
    The project you are currently tasked with is the webfg-app which you should already have or can clone from here: https://github.com/phnks/webfg-app.git. 
    It is a TTRPG platform that includes the webfg-gql backend, the webfg-gm-app for the game master, and eventually in the future the webfg-player-app for the players. 
    It contains all the data needed for characters, objects, actions, and to track encounters. 
    It is fully built and hosted on AWS. All the relevant commands you need to deploy and test the services you can find the in relevant package.jsons and/or README.md files. 

    When you are given a task for this project, the first thing you must ensure is that you have a feature branch for your task. Never work directly on master.
    Once you have your feature branch, you must ensure that you have a pull request (PR) for that branch. There can only ever be 1 PR for each branch. You can use the `gh` cli tool to check for PRs to see if one already exists for your feature branch. 
    If a PR does not exist for your feature branch create one using the same `gh` cli command.
    Once you have a PR for your feature branch, ensure you remember the PR number. The PR number serves as your DEPLOYMENT_ID when testing any of your code changes.

    This project has CICD using github actions which you can find under the .github folder. Each time you push a change to a remote branch that has a PR (and all feature branches should always have 1 PR), 
    the github action will trigger and automatically deploy all your changes to a new environment tagged with your DEPLOYMENT_ID which is the same as your PR number. For example if your PR number is 69 it will automatically deploy webfg-gm-app-qa69 and webfg-gql-qa69.
    You should ALWAYS still deploy manually using the commands in the package.json. For example: `DEPLOYMENT_ID=69 npm run deploy:qa`. You should ALWAYS do this manual deployment since if your code changes cause it to fail you'll want to know the failure reason. The github action will not tell you if it failed.
    You can use the `check-deploy:qa` comcommand as well to check the root cause of any deployment failure. For example: `DEPLOYMENT_ID=69 npm run check-deploy:qa` would tell you the status of the deployment for DEPLOYMENT_ID 69 which is for PR number 69.
    For example, if you run `DEPLOYMENT_ID=69 npm run deploy:qa` and are told that it failed, often the error will be from AWS CloudFormation and look something like ROLLBACK_COMPLETE or ROLLBACK_UPDATE_COMPLETE which means it failed and was rolled back by AWS.
    If you run: `DEPLOYMENT_ID=69 npm run check-deploy:qa` it would tell you the exact reason AWS failed and chose to roll it back, which tells you what you need to fix before trying to deploy again.

    webfg-gm-app is only for the react web frontend, and webfg-gql is only for the graphql backend. 
    If your changes only affect the frontend you only need to deploy webfg-gm-app to test your changes
    If your changes only affect the backend graphql or databases then you only need to deploy webfg-gql to test your changes.
    Only deploy both webfg-gm-app and webfg-gql if your changes include both backend and frontend changes
    It can take over 15 mins to depoy webfg-gql and over 5 mins to deploy webfg-gm-app so please make sure you only deploy when you have made changes in the respective apps to save time

    If you make ANY schema changes in webfg-gql, you MUST increment the schema version in the package.json for both qa and prod. If you don't do this your changes will not be reflected as AWS CloudFormation will not detect a schema change.

    In this project, whenever you finish a task, please run the necessary commands in terminal to test your code changes by running the deploy:qa commands as already stated, then confirming they worked using the check-deploy:qa commands as also previously stated.
    Then the user will test your code changes manually, simulating a real user of the application. 
    Only once the user has confirmed that the task is complete, that there are no errors and no bugs, perform the following steps:

    1. Update the PR for your feature branch to include any additional code changes you made for this task, use the `gh` cli for this
    2. On the PR make sure to include a detailed description of all the changes you made and in which files, why you made those changes, and then also describe any uncertainties or issues you encountered. If the PR description already exists make sure to update it
    3. Add all files you have made changes to using the `git add` command
    4. Then commit the files you added by using the `git commit` command, providing a descriptive commit message of what the changes include
    5. Push your commit using `git push`, confirm that it was pushed successfully
    6. Then tell the user that the task is complete, and that you added, committed, and pushed the changes successfully. Please provide a link to your PR so that the user can review your code changes

    You have full permissions for git, gh cli, aws, and sam for this project including full sudo access
    If you run into issues with `git` such as getting messages like `nothing to commit, working tree clean` or other errors, repeat the same steps 3-5 but with `sudo` as sometimes the changes may only be staged for the root user
  """

  return webfg_app_prompt