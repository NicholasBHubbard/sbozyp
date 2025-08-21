#compdef sbozyp

_sbozyp_command_prefix() {
    local config_file_opt=
    local repo_opt=
    local i=2

    while [[ $i -lt ${#words[@]} ]]; do
        local word=${words[i]}
        local next=${words[i+1]}
        if [[ $word == -F && -z $config_file_opt ]]; then
            config_file_opt="-F $next"
            ((i++))
        elif [[ $word == -R && -z $repo_opt ]]; then
            repo_opt="-R $next"
            ((i++))
        fi
        ((i++))
    done

    printf "%s %s" "$repo_opt" "$config_file_opt";
}

_sbozyp_config_file() {
    local config_file=$([[ -f $HOME/.sbozyp.conf ]] && printf '%s' "$HOME/.sbozyp.conf" || printf '%s' /etc/sbozyp/sbozyp.conf)
    if [[ $(_sbozyp_command_prefix) =~ -F[[:space:]](.+) ]]; then
        config_file=$(eval printf '%s' "${match[1]}")
    fi
    printf '%s' "$config_file"
}

_sbozyp_determine_command() {
    local i=2
    local command=

    while [[ $i -lt ${#words[@]} ]]; do
        local word=${words[i]}
        case $word in
            -F|-R)
                ((i++))
                ;;
            install|in|build|bu|remove|rm|query|qr|search|se|null|nu)
                command=$word
                break
                ;;
        esac
        ((i++))
    done

    printf '%s' "$command"
}

_sbozyp_complete() {
    local cur=$words[$CURRENT]
    local prev=$words[$CURRENT-1]

    local global_opts="-C -F -R -S --help --version"

    local commands="install build remove query search null"

    if [[ $prev == -F ]]; then
        _files
        return
    elif [[ $prev == -R ]]; then
        local repos=$(awk -F' *= *' '/REPO_[0-9]+_NAME/ {print $2}' "$(_sbozyp_config_file)" 2>/dev/null)
        compadd -X "repositories" -- ${(f)repos}
        return
    fi

    local command=$(_sbozyp_determine_command)

    case $command in
        install|in)
            local opts="--help -f -i -k -n"
            if [[ $cur == in ]]; then
                compadd -U -- "install"
            elif [[ $cur == -* ]]; then
                compadd -X "options" -- ${=opts}
            else
                local all_prgnams=$(sbozyp $(_sbozyp_command_prefix) search -p '' 2>/dev/null)
                compadd -X "packages" -- ${(f)all_prgnams}
            fi
            ;;
        build|bu)
            local opts="--help -f -i"
            if [[ $cur == bu ]]; then
                compadd -U -- "build"
            elif [[ $cur == -* ]]; then
                compadd -X "options" -- ${=opts}
            else
                local all_prgnams=$(sbozyp $(_sbozyp_command_prefix) search -p '' 2>/dev/null)
                compadd -X "packages" -- ${(f)all_prgnams}
            fi
            ;;
        null|nu)
            local opts="--help"
            if [[ $cur == nu ]]; then
                compadd -U -- "null"
            else
                compadd -X "options" -- ${=opts}
            fi
            ;;
        query|qr)
            local opts="--help -a -d -i -p -q -r -s -u"
            if [[ $cur == qr ]]; then
                compadd -U -- "query"
            elif [[ $cur == -* ]]; then
                compadd -X "options" -- ${=opts}
            else
                local all_prgnams=$(sbozyp $(_sbozyp_command_prefix) search -p '' 2>/dev/null)
                compadd -X "packages" -- ${(f)all_prgnams}
            fi
            ;;
        remove|rm)
            local opts="--help -i"
            if [[ $cur == rm ]]; then
                compadd -U -- "remove"
            elif [[ $cur == -* ]]; then
                compadd -X "options" -- ${=opts}
            else
                local installed_packages=$(sbozyp $(_sbozyp_command_prefix) query -a 2>/dev/null | cut -d'/' -f2 | sort)
                compadd -X "installed packages" -- ${(f)installed_packages}
            fi
            ;;
        search|se)
            local opts="--help -c -n -p"
            if [[ $cur == se ]]; then
                compadd -U -- "search"
            else
                compadd -X "options" -- ${=opts}
            fi
            ;;
        *)
            if [[ $cur == -* ]]; then
                compadd -X "global options" -- ${=global_opts}
            else
                compadd -X "commands" -- ${=commands}
            fi
            ;;
    esac

    return 0
}

compdef _sbozyp_complete sbozyp
