classdef CodeIssuesTest < matlab.unittest.TestCase
%CODEISSUESTEST The Code Analyzer finds nothing in the package or its tests.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function thePackageAndItsTestsHaveNoCodeIssue(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            found = codeIssues(root);
            % Every MATLAB file of the repository was analysed, so that no
            % issue means no issue rather than no file.
            files = dir(fullfile(root, "**", "*.m"));
            testCase.verifyGreaterThan(numel(files), 30);
            paths = string({files.folder}) + filesep + string({files.name});
            missing = setdiff(paths, string(found.Files));
            testCase.verifyEmpty(missing, formattedDisplayText(missing));
            testCase.verifyEmpty(found.Issues, formattedDisplayText(found.Issues));
        end
    end
end
